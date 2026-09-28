-- Rebuild the analysis-ready, one-row-per-CNPJ-basic cohort for the seven ABC cities.
-- Only head offices located in the ABC are included; branch registrations are not
-- counted as separate businesses. CNPJ basic identifiers remain text (8 characters).

CREATE OR REPLACE FUNCTION raw.safe_yyyymmdd(value TEXT)
RETURNS DATE
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE y INTEGER; m INTEGER; d INTEGER; max_day INTEGER;
BEGIN
    IF value IS NULL OR value !~ '^[0-9]{8}$' THEN RETURN NULL; END IF;
    y := substring(value, 1, 4)::INTEGER;
    m := substring(value, 5, 2)::INTEGER;
    d := substring(value, 7, 2)::INTEGER;
    IF y < 1800 OR y > 9999 OR m < 1 OR m > 12 OR d < 1 THEN RETURN NULL; END IF;
    max_day := extract(day FROM (make_date(y, m, 1) + interval '1 month - 1 day'))::INTEGER;
    IF d > max_day THEN RETURN NULL; END IF;
    RETURN make_date(y, m, d);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE INDEX IF NOT EXISTS ix_establishment_cnpj_basic ON raw.establishment (cnpj_basic);
CREATE INDEX IF NOT EXISTS ix_establishment_municipality ON raw.establishment (state_code, municipality_code, head_office_or_branch);
CREATE INDEX IF NOT EXISTS ix_company_cnpj_basic ON raw.company (cnpj_basic);
CREATE INDEX IF NOT EXISTS ix_simples_cnpj_basic ON raw.simples (cnpj_basic);
CREATE INDEX IF NOT EXISTS ix_municipality_code ON ref.municipality (code);
CREATE INDEX IF NOT EXISTS ix_cnae_code ON ref.cnae (code);
ANALYZE raw.company;
ANALYZE raw.establishment;
ANALYZE raw.simples;
ANALYZE ref.municipality;
ANALYZE ref.cnae;

-- RFB municipality codes are not assumed to be IBGE codes. Match normalized names.
DROP VIEW IF EXISTS analytics.data_quality;
DROP TABLE IF EXISTS analytics.business_cohort;
CREATE TABLE analytics.business_cohort AS
WITH target_city_aliases(alias_normalized, city_name) AS (
    VALUES
      ('santoandre', 'Santo André'),
      ('saobernardodocampo', 'São Bernardo do Campo'),
      ('saobernardo', 'São Bernardo do Campo'),
      ('saocaetanodosul', 'São Caetano do Sul'),
      ('saocaetano', 'São Caetano do Sul'),
      ('diadema', 'Diadema'),
      ('maua', 'Mauá'),
      ('ribeiraopires', 'Ribeirão Pires'),
      ('riograndedaserra', 'Rio Grande da Serra')
), target_municipality AS (
    SELECT DISTINCT m.code, a.city_name
    FROM ref.municipality m
    JOIN target_city_aliases a
      ON regexp_replace(public.unaccent(lower(trim(m.description))), '[^a-z0-9]', '', 'g') = a.alias_normalized
), company_one AS (
    SELECT DISTINCT ON (cnpj_basic) *
    FROM raw.company
    WHERE cnpj_basic IS NOT NULL AND trim(cnpj_basic) <> ''
    ORDER BY cnpj_basic, company_size_code
), simples_one AS (
    SELECT DISTINCT ON (cnpj_basic) *
    FROM raw.simples
    WHERE cnpj_basic IS NOT NULL AND trim(cnpj_basic) <> ''
    ORDER BY cnpj_basic,
             (upper(trim(coalesce(mei_option, ''))) = 'S') DESC,
             (upper(trim(coalesce(simples_option, ''))) = 'S') DESC,
             raw.safe_yyyymmdd(mei_option_date) DESC NULLS LAST
), matrix_candidates AS (
    SELECT
      trim(e.cnpj_basic) AS cnpj_basic,
      city.city_name AS municipality,
      trim(e.municipality_code) AS municipality_code_rfb,
      upper(trim(e.state_code)) AS state_code,
      raw.safe_yyyymmdd(e.activity_start_date) AS opened_at,
      trim(e.registration_status) AS registration_status_code,
      raw.safe_yyyymmdd(e.status_date) AS registration_status_date,
      NULLIF(trim(e.primary_cnae_code), '') AS primary_cnae_code,
      NULLIF(trim(cnae.description), '') AS primary_cnae_description,
      trim(c.company_size_code) AS company_size_code,
      NULLIF(trim(c.capital_social), '') AS capital_social_raw,
      trim(s.simples_option) AS simples_option,
      raw.safe_yyyymmdd(s.simples_option_date) AS simples_option_date,
      raw.safe_yyyymmdd(s.simples_exclusion_date) AS simples_exclusion_date,
      trim(s.mei_option) AS mei_option,
      raw.safe_yyyymmdd(s.mei_option_date) AS mei_option_date,
      raw.safe_yyyymmdd(s.mei_exclusion_date) AS mei_exclusion_date,
      (SELECT snapshot_date FROM meta.snapshot WHERE singleton) AS snapshot_date
    FROM raw.establishment e
    JOIN target_municipality city ON city.code = trim(e.municipality_code)
    JOIN company_one c ON trim(c.cnpj_basic) = trim(e.cnpj_basic)
    LEFT JOIN simples_one s ON trim(s.cnpj_basic) = trim(e.cnpj_basic)
    LEFT JOIN ref.cnae cnae ON trim(cnae.code) = trim(e.primary_cnae_code)
    WHERE upper(trim(e.state_code)) = 'SP'
      AND trim(e.head_office_or_branch) = '1'
      AND trim(c.company_size_code) IN ('01', '03')
)
SELECT DISTINCT ON (cnpj_basic)
    cnpj_basic,
    municipality,
    municipality_code_rfb,
    state_code,
    opened_at,
    registration_status_code,
    registration_status_date,
    (registration_status_code = '08' AND registration_status_date IS NOT NULL
      AND registration_status_date <= snapshot_date) AS is_closed,
    CASE WHEN registration_status_code = '08' AND registration_status_date IS NOT NULL
      AND registration_status_date <= snapshot_date THEN registration_status_date END AS closed_at,
    primary_cnae_code,
    primary_cnae_description,
    left(primary_cnae_code, 2) AS cnae_division,
    CASE company_size_code WHEN '01' THEN 'ME' WHEN '03' THEN 'EPP' END AS company_size,
    CASE WHEN capital_social_raw ~ '^\s*[0-9]+(\.[0-9]+)?\s*$'
         THEN capital_social_raw::NUMERIC ELSE NULL END AS capital_social,
    CASE WHEN upper(trim(coalesce(simples_option, ''))) = 'S' THEN TRUE
         WHEN upper(trim(coalesce(simples_option, ''))) = 'N' THEN FALSE ELSE NULL END AS is_simples,
    CASE WHEN upper(trim(coalesce(mei_option, ''))) = 'S' THEN TRUE
         WHEN upper(trim(coalesce(mei_option, ''))) = 'N' THEN FALSE ELSE NULL END AS is_mei,
    simples_option_date,
    simples_exclusion_date,
    mei_option_date,
    mei_exclusion_date,
    snapshot_date
FROM matrix_candidates
ORDER BY cnpj_basic, registration_status_date DESC NULLS LAST, opened_at ASC NULLS LAST;

CREATE UNIQUE INDEX ix_business_cohort_cnpj ON analytics.business_cohort (cnpj_basic);
CREATE INDEX ix_business_cohort_city ON analytics.business_cohort (municipality);
CREATE INDEX ix_business_cohort_sector ON analytics.business_cohort (cnae_division);
ANALYZE analytics.business_cohort;

CREATE OR REPLACE VIEW analytics.data_quality AS
SELECT 'raw_company_rows' AS check_name, count(*)::BIGINT AS check_value FROM raw.company
UNION ALL SELECT 'raw_establishment_rows', count(*) FROM raw.establishment
UNION ALL SELECT 'raw_simples_rows', count(*) FROM raw.simples
UNION ALL SELECT 'cohort_municipalities_present', count(DISTINCT municipality) FROM analytics.business_cohort
UNION ALL SELECT 'cohort_businesses', count(*) FROM analytics.business_cohort
UNION ALL SELECT 'duplicate_business_ids_after_deduplication', count(*) - count(DISTINCT cnpj_basic) FROM analytics.business_cohort
UNION ALL SELECT 'duplicate_company_ids_in_raw', count(*) FROM (SELECT cnpj_basic FROM raw.company GROUP BY cnpj_basic HAVING count(*) > 1) duplicates
UNION ALL SELECT 'duplicate_head_office_ids_in_raw', count(*) FROM (SELECT cnpj_basic FROM raw.establishment WHERE trim(head_office_or_branch) = '1' GROUP BY cnpj_basic HAVING count(*) > 1) duplicates
UNION ALL SELECT 'missing_opening_dates', count(*) FILTER (WHERE opened_at IS NULL) FROM analytics.business_cohort
UNION ALL SELECT 'missing_registration_status', count(*) FILTER (WHERE registration_status_code IS NULL OR trim(registration_status_code) = '') FROM analytics.business_cohort
UNION ALL SELECT 'missing_primary_cnae', count(*) FILTER (WHERE primary_cnae_code IS NULL) FROM analytics.business_cohort
UNION ALL SELECT 'closed_without_valid_date', count(*) FILTER (WHERE registration_status_code = '08' AND (registration_status_date IS NULL OR registration_status_date > snapshot_date)) FROM analytics.business_cohort;
