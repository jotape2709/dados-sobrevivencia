-- Raw RFB CNPJ snapshot. All identifiers and CSV fields stay TEXT until validated.
-- This safely preserves leading zeroes and the alphanumeric CNPJ introduced in 2026.
CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS analytics;
CREATE SCHEMA IF NOT EXISTS meta;

CREATE TABLE IF NOT EXISTS raw.company (
    cnpj_basic TEXT, legal_name TEXT, legal_nature_code TEXT,
    responsible_qualification_code TEXT, capital_social TEXT,
    company_size_code TEXT, responsible_federal_entity TEXT
);
CREATE TABLE IF NOT EXISTS raw.establishment (
    cnpj_basic TEXT, cnpj_order TEXT, cnpj_check_digits TEXT,
    head_office_or_branch TEXT, trade_name TEXT, registration_status TEXT,
    status_date TEXT, status_reason_code TEXT, foreign_city TEXT,
    country_code TEXT, activity_start_date TEXT, primary_cnae_code TEXT,
    secondary_cnae_codes TEXT, address_type TEXT, street_name TEXT,
    street_number TEXT, address_complement TEXT, neighborhood TEXT,
    postal_code TEXT, state_code TEXT, municipality_code TEXT,
    area_code_1 TEXT, phone_1 TEXT, area_code_2 TEXT, phone_2 TEXT,
    fax_area_code TEXT, fax_number TEXT, business_email TEXT,
    special_status TEXT, special_status_date TEXT
);
CREATE TABLE IF NOT EXISTS raw.simples (
    cnpj_basic TEXT, simples_option TEXT, simples_option_date TEXT,
    simples_exclusion_date TEXT, mei_option TEXT, mei_option_date TEXT,
    mei_exclusion_date TEXT
);
CREATE TABLE IF NOT EXISTS ref.cnae (code TEXT, description TEXT);
CREATE TABLE IF NOT EXISTS ref.municipality (code TEXT, description TEXT);

CREATE TABLE IF NOT EXISTS meta.snapshot (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    snapshot_month TEXT NOT NULL,
    snapshot_date DATE NOT NULL,
    source_url TEXT NOT NULL,
    downloaded_at_utc TIMESTAMPTZ,
    loaded_at_utc TIMESTAMPTZ NOT NULL DEFAULT now()
);
