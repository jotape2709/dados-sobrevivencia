#!/usr/bin/env bash
# Download the latest official RFB CNPJ snapshot, excluding Socios*.zip by design.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${CNPJ_BASE_URL:-https://arquivos.receitafederal.gov.br/dados/cnpj/dados_abertos_cnpj/}"
RAW_DIR="${RAW_DIR:-$ROOT/data/raw}"
EXTRACT_DIR="${EXTRACT_DIR:-$ROOT/data/extracted}"
MANIFEST="$RAW_DIR/manifest.json"
mkdir -p "$RAW_DIR" "$EXTRACT_DIR"

command -v wget >/dev/null || { echo "ERROR: wget is required." >&2; exit 1; }
command -v unzip >/dev/null || { echo "ERROR: unzip is required." >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 is required." >&2; exit 1; }

python3 "$ROOT/scripts/discover_downloads.py" --base-url "$BASE_URL" --manifest "$MANIFEST"
python3 - "$MANIFEST" <<'PY' > "$RAW_DIR/download-urls.txt"
import json, sys
manifest=json.load(open(sys.argv[1], encoding="utf-8"))
for group in ("companies", "establishments", "simples", "cnaes", "municipalities"):
    for url in manifest["selected_files"][group]:
        print(url)
PY

while IFS= read -r url; do
  [[ -n "$url" ]] || continue
  filename="${url##*/}"
  echo "Downloading $filename"
  wget --continue --tries=5 --waitretry=5 --timeout=60 --output-document="$RAW_DIR/$filename" "$url"
done < "$RAW_DIR/download-urls.txt"

while IFS= read -r url; do
  [[ -n "$url" ]] || continue
  filename="${url##*/}"
  echo "Extracting $filename"
  unzip -oq "$RAW_DIR/$filename" -d "$EXTRACT_DIR"
done < "$RAW_DIR/download-urls.txt"

python3 - "$MANIFEST" "$RAW_DIR" <<'PY'
import hashlib, json, pathlib, sys
manifest_path=pathlib.Path(sys.argv[1]); raw=pathlib.Path(sys.argv[2])
manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
checksums={}
for paths in manifest["selected_files"].values():
    for url in paths:
        f=raw/url.rsplit("/",1)[-1]
        h=hashlib.sha256()
        with f.open("rb") as stream:
            for block in iter(lambda: stream.read(1024*1024), b""): h.update(block)
        checksums[f.name]=h.hexdigest()
manifest["sha256"] = checksums
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
PY

echo "Download and extraction complete. Snapshot: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["snapshot_month"])' "$MANIFEST")"
echo "Next: make load (see README.md for storage and database prerequisites)."
