import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import discover_downloads as resolver


class DiscoveryTests(unittest.TestCase):
    def test_choose_latest_month(self):
        self.assertEqual(resolver.choose_latest_month(["2026-06/", "2026-08/", "2026-07/"]), "2026-08")

    def test_selects_required_groups_and_excludes_partners(self):
        links = [
            "Empresas0.zip", "Empresas1.zip", "Estabelecimentos0.zip", "Simples.zip",
            "Cnaes.zip", "Municipios.zip", "Socios0.zip",
        ]
        found = resolver.select_required_files(links)
        self.assertEqual(len(found["companies"]), 2)
        self.assertNotIn("partners", found)
        self.assertTrue(all("socio" not in name.casefold() for group in found.values() for name in group))
        self.assertEqual(set(found), {"companies", "establishments", "simples", "cnaes", "municipalities"})

    def test_missing_group_is_actionable(self):
        with self.assertRaisesRegex(ValueError, "municipalities"):
            resolver.select_required_files(["Empresas0.zip", "Estabelecimentos0.zip", "Simples.zip", "Cnaes.zip"])

    def test_case_insensitive_archives(self):
        found = resolver.select_required_files(["EMPRESAS0.ZIP", "ESTABELECIMENTOS0.ZIP", "SIMPLES.ZIP", "CNAES.ZIP", "MUNICIPIOS.ZIP"])
        self.assertTrue(all(found.values()))


if __name__ == "__main__":
    unittest.main()
