#!/usr/bin/env python3
"""Discover the latest public RFB CNPJ snapshot without selecting the partners file."""
from __future__ import annotations

import argparse
import html.parser
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

MONTH_RE = re.compile(r"^\d{4}-\d{2}/?$")
GROUPS = {
    "companies": re.compile(r"^Empresas\d*\.zip$", re.I),
    "establishments": re.compile(r"^Estabelecimentos\d*\.zip$", re.I),
    "simples": re.compile(r"^Simples\d*\.zip$", re.I),
    "cnaes": re.compile(r"^Cnaes\.zip$", re.I),
    "municipalities": re.compile(r"^Municipios\.zip$", re.I),
}

class Links(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.hrefs: list[str] = []
    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() == "a":
            href = dict(attrs).get("href")
            if href:
                self.hrefs.append(href)

@dataclass
class Snapshot:
    month: str
    files: list[str]


def get_html(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "dados-sobrevivencia-abc/1.0 (research; public data)"})
    with urllib.request.urlopen(req, timeout=60) as response:
        return response.read().decode("utf-8", errors="replace")


def parse_links(document: str) -> list[str]:
    parser = Links()
    parser.feed(document)
    return parser.hrefs


def choose_latest_month(month_links: list[str]) -> str:
    months = sorted({link.rstrip("/") for link in month_links if MONTH_RE.fullmatch(link.rstrip("/") + "/") or re.fullmatch(r"\d{4}-\d{2}", link.rstrip("/"))})
    if not months:
        raise ValueError("No YYYY-MM snapshot directory was found in the official index.")
    return months[-1]


def select_required_files(links: list[str]) -> dict[str, list[str]]:
    selected = {group: [] for group in GROUPS}
    for link in links:
        name = urllib.parse.unquote(urllib.parse.urlparse(link).path.rsplit("/", 1)[-1])
        if "socio" in name.casefold():
            continue
        for group, pattern in GROUPS.items():
            if pattern.fullmatch(name):
                selected[group].append(link)
                break
    missing = [group for group, files in selected.items() if not files]
    if missing:
        raise ValueError("Official snapshot is missing expected ZIP group(s): " + ", ".join(missing))
    return selected


def discover(base_url: str) -> tuple[str, dict[str, list[str]]]:
    base = base_url.rstrip("/") + "/"
    root_links = parse_links(get_html(base))
    month = choose_latest_month(root_links)
    snapshot_url = urllib.parse.urljoin(base, month + "/")
    file_links = parse_links(get_html(snapshot_url))
    selected = select_required_files(file_links)
    absolute = {group: sorted({urllib.parse.urljoin(snapshot_url, link) for link in files}) for group, files in selected.items()}
    return month, absolute


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="https://arquivos.receitafederal.gov.br/dados/cnpj/dados_abertos_cnpj/", help="Official RFB CNPJ archive index (override if the portal changes).")
    parser.add_argument("--manifest", type=Path, help="Write a JSON manifest instead of printing one URL per line.")
    args = parser.parse_args()
    try:
        month, files = discover(args.base_url)
        flat = [url for group in files.values() for url in group]
        manifest = {
            "source": "Receita Federal do Brasil (RFB), Dados Abertos do CNPJ",
            "base_url": args.base_url,
            "snapshot_month": month,
            "downloaded_at_utc": datetime.now(timezone.utc).isoformat(),
            "selected_files": files,
            "excluded": "Socios*.zip is deliberately never selected.",
        }
        if args.manifest:
            args.manifest.parent.mkdir(parents=True, exist_ok=True)
            args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"Snapshot {month}: {len(flat)} ZIP file(s); manifest: {args.manifest}", file=sys.stderr)
        else:
            print("\n".join(flat))
        return 0
    except Exception as exc:  # surface network/index changes with a useful message
        print(f"CNPJ source discovery failed: {exc}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
