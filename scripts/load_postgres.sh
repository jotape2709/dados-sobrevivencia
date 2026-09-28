#!/usr/bin/env bash
# Load the full selected RFB monthly dump into local PostgreSQL, then materialize the ABC cohort.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then set -a; # shellcheck disable=SC1091
  source "$ROOT/.env"; set +a
fi
: "${POSTGRES_PASSWORD:?Copy .env.example to .env and set POSTGRES_PASSWORD}"
export PGHOST="${POSTGRES_HOST:-localhost}" PGPORT="${POSTGRES_PORT:-5432}"
export PGDATABASE="${POSTGRES_DB:-survival_abc}" PGUSER="${POSTGRES_USER:-analyst}"
export PGPASSWORD="$POSTGRES_PASSWORD"
EXTRACT_DIR="${EXTRACT_DIR:-$ROOT/data/extracted}"
MANIFEST="${MANIFEST:-$ROOT/data/raw/manifest.json}"

for tool in psql python3 find; do command -v "$tool" >/dev/null || { echo "ERROR: $tool is required." >&2; exit 1; }; done
[[ -s "$MANIFEST" ]] || { echo "ERROR: manifest not found at $MANIFEST; run make download first." >&2; exit 1; }

# The latest directory name is YYYY-MM. Use its month end as a conservative snapshot cutoff.
SNAPSHOT_DATE="${RFB_SNAPSHOT_DATE:-$(python3 - "$MANIFEST" <<'PY'
import calendar, json, sys
month=json.load(open(sys.argv[1], encoding="utf-8"))["snapshot_month"]
y, m=map(int, month.split("-"))
print(f"{y:04d}-{m:02d}-{calendar.monthrange(y,m)[1]:02d}")
PY
)}"
SNAPSHOT_MONTH="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["snapshot_month"])' "$MANIFEST")"
SOURCE_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))["base_url"])' "$MANIFEST")"

psql -v ON_ERROR_STOP=1 -f "$ROOT/sql/001_schema.sql"
psql -v ON_ERROR_STOP=1 -c 'TRUNCATE raw.company, raw.establishment, raw.simples, ref.cnae, ref.municipality CASCADE;'

load_group() {
  local pattern="$1" table="$2" count=0 file escaped
  while IFS= read -r -d '' file; do
    escaped="${file//\'/\'\'}"
    echo "Loading $(basename "$file") -> $table"
    psql -v ON_ERROR_STOP=1 -c "\\copy $table FROM '$escaped' WITH (FORMAT csv, DELIMITER ';', QUOTE '\"', ESCAPE '\"', NULL '', ENCODING 'LATIN1')"
    ((count+=1))
  done < <(find "$EXTRACT_DIR" -type f -iname "$pattern" -print0 | sort -z)
  (( count > 0 )) || { echo "ERROR: no extracted CSVs matching $pattern in $EXTRACT_DIR" >&2; exit 1; }
  echo "Loaded $count file(s) into $table"
}

load_group 'Empresas*.csv' raw.company
load_group 'Estabelecimentos*.csv' raw.establishment
load_group 'Simples*.csv' raw.simples
load_group 'Cnaes*.csv' ref.cnae
load_group 'Municipios*.csv' ref.municipality

psql -v ON_ERROR_STOP=1 -v snapshot_date="$SNAPSHOT_DATE" -v snapshot_month="$SNAPSHOT_MONTH" -v source_url="$SOURCE_URL" <<'SQL'
INSERT INTO meta.snapshot(singleton, snapshot_month, snapshot_date, source_url, downloaded_at_utc)
VALUES (TRUE, :'snapshot_month', :'snapshot_date'::DATE, :'source_url', NULL)
ON CONFLICT (singleton) DO UPDATE SET
  snapshot_month=EXCLUDED.snapshot_month,
  snapshot_date=EXCLUDED.snapshot_date,
  source_url=EXCLUDED.source_url,
  loaded_at_utc=now();
SQL

psql -v ON_ERROR_STOP=1 -f "$ROOT/sql/002_transform.sql"
psql -v ON_ERROR_STOP=1 -c 'TABLE analytics.data_quality;'
echo "PostgreSQL load and cohort build complete (snapshot $SNAPSHOT_MONTH; as-of $SNAPSHOT_DATE)."
