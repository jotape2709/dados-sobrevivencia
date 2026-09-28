# Methodology and interpretation

## Research question and target population

This project describes the registered survival of micro and small enterprise head offices in seven municipalities of the ABC Paulista region: Santo André, São Bernardo do Campo, São Caetano do Sul, Diadema, Mauá, Ribeirão Pires and Rio Grande da Serra.

**Unit:** one legal-person root (CNPJ basic, eight leading characters), represented by its head-office registration (establishment order 0001). **Geography:** the RFB municipality code resolved through the official municipality lookup and normalized place-name aliases, plus UF = SP. This avoids assuming Receita municipality codes equal IBGE codes. **Size:** RFB company-size codes 01 (ME) and 03 (EPP). **Time origin:** the head-office activity-start date.

The cohort is a snapshot of registrations whose headquarters are in the region. It omits firms headquartered elsewhere even when they have local branches. Branches are not separate analytical firms.

## Event and censoring

The observed event is the head office's RFB registration status “baixada” (code 08), dated by the establishment's status-date field. Every other registration status is treated as right-censored at the snapshot cutoff. The default cutoff is the final calendar day of the selected `YYYY-MM` source directory; set `RFB_SNAPSHOT_DATE` only if an authoritative finer-grained extraction date is available.

For an observed event, duration = valid baixa date − valid activity-start date. For a right-censored record, duration = snapshot date − activity-start date. Invalid dates, start-after-cutoff, event-before-start, event-date-after-cutoff, and a baixada with no valid status date are reported and excluded from time-to-event models. Dates are never silently imputed. Duplicated CNPJ basics are resolved to one head-office record deterministically; the cohort then enforces a unique key.

This is **administrative registration survival**. A baixa can be administrative, retroactive or unrelated to economic failure. The status on the head office does not establish whether branches continue operating. The data do not observe informal activity or precise economic cessation. Censoring may be informative, registry coverage may be delayed, and periodic snapshots can revise earlier records.

## Descriptive analysis

Counts of openings use activity-start year; counts of closures use observed valid baixa year. Municipal and two-digit CNAE-division summaries show counts, share with an observed administrative closure at the snapshot, MEI coverage/share, median observed duration and registered capital. The “share closed” in these cross-sectional summaries is **not a survival probability**; it mixes cohorts with different exposure lengths and must not be compared as a causal risk without a defined follow-up design.

CNAE division is the first two characters of the primary CNAE code. MEI/Simples is the latest cross-sectional attribute supplied by the monthly Simples file, not necessarily historical status at each point in a company's lifetime. Capital is declared social capital, not revenue, cash or net worth.

## Survival curves and regression

- Kaplan–Meier curves estimate the survival function for time until observed head-office administrative baixa. Active/unclosed records are censored at the selected snapshot cutoff.
- Curves are shown for MEI vs. non-MEI among known values and for the largest CNAE divisions. Other divisions are omitted from the sector curve for readability; all remain in descriptive summaries.
- Cox regression reports hazard ratios and 95% Wald/profile confidence intervals as available from the `broom` methods. Predictors are CNAE group, MEI, municipality, company size and log(1 + declared capital). Unknown MEI, unknown size, and incomplete model predictors are not imputed. A minimum-event guard avoids estimates when there are fewer than ten observed events or twenty usable records. Check `cox_ph_assumption.txt`; violation of proportional hazards undermines a single average HR.
- Observational records may share unobserved causes, covariates may be measured after opening, sector/capital can be incomplete, and the public extract provides no reliable causal design. Regression coefficients are conditional **associations with registry baixa**, not causal effects or personal/business risk scores.

## Two-year endpoint

For each valid record, define event = 1 only if a valid status-08 baixa occurs by 730 days after opening. Define event = 0 only for records with the entire 730-day period observable by the snapshot and no such event by day 730. Businesses opened too recently to have a full window are excluded; they are not labelled “survived two years.” A logistic model is estimated only if there are more than twenty mature observations and both endpoint classes. Report odds ratios and 95% Wald intervals, not relative-risk language.

## Clustering

Clustering is performed over two-digit CNAE divisions meeting a minimum of 30 MPE head-office records and complete features: MEI share, administrative baixa within 730 days among the eligible mature records, mean observed age, and log mean registered capital. Features are standardized before Euclidean distance/k-means. A fixed seed makes the run reproducible. Candidate k (2 through at most 6) is scored by total within-cluster sum of squares (elbow curve) and average silhouette; k is selected by the greatest candidate mean silhouette. Ward.D2 hierarchical clustering is cut at the same k for comparison.

This aggregate-level matrix usually contains few groups and may be unstable; report group counts, diagnostics and source month. Clusters are descriptive, not “true” industry types, forecasts or firm-level classifications. If coverage is insufficient, clustering is explicitly skipped.

## Data quality and privacy

- CSV input uses the official positional layouts: Company (7 fields), Establishment (30), Simples (7), CNAE (2), Municipality (2); separators are semicolons, encoding is Latin-1 during COPY to a UTF-8 database. Validate current layouts at the official [RFB metadata PDF](https://www.gov.br/receitafederal/dados/cnpj-metadados.pdf) before using a future release.
- CNPJ identifiers are text, preserving leading zeros and alphanumeric new registrations. Numeric casts are limited to validated registered capital and numeric model features.
- Date parsing checks calendar validity, including leap years. Unknown classifications remain missing/unknown; invalid dates are surfaced in quality outputs.
- The **Sócios** archive is excluded entirely. The target question needs neither partners' names nor partially masked personal identifiers. Names, contact details and street addresses are also not carried into the analytics-ready table. Raw source archives still remain on the analyst's local disk until the analyst removes them.
- Keep source files and credentials private, avoid committing `.env`, and do not publish a row-level company risk list.

## Reproducibility

Record repository commit, archive month, download time, source URL, ZIP hashes and snapshot cutoff. Refresh RFB metadata and file naming assumptions before each new ingestion cycle. Re-run tests, quality checks and all outputs together; never combine coefficients from one source month with charts from another.
