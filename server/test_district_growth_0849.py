from __future__ import annotations
import copy
import unittest
from server import economy

class DistrictGrowthTests(unittest.TestCase):
    def setUp(self):
        self.w = economy.new_world()
    def test_district_estimates_are_deterministic(self):
        first = economy.district_demand(self.w, "player")
        self.assertEqual(first, economy.district_demand(self.w, "player"))
        self.assertTrue(first)
        self.assertTrue(all(x["estimated_bread_demand_per_tick"] >= 0 for x in first))
        self.assertTrue(all(x["competition_level"] in ("low", "medium", "high") for x in first))
    def test_growth_is_scoped_and_read_only(self):
        before = copy.deepcopy(self.w)
        player = economy.company_growth(self.w, "player")
        rival = economy.company_growth(self.w, "rival")
        self.assertEqual(player["facility_count"], sum(f["owner"] == "player" for f in self.w["facilities"].values()))
        self.assertEqual(rival["facility_count"], sum(f["owner"] == "rival" for f in self.w["facilities"].values()))
        self.assertEqual(len(player["goals"]), 3)
        self.assertEqual(self.w, before)
    def test_snapshot_and_invariants(self):
        s = economy.snapshot(self.w, "player")
        self.assertIn("district_demand", s)
        self.assertIn("company_growth", s)
        self.assertEqual(s["company_growth"]["completed_goals"], sum(
            g["current"] >= g["target"] for g in s["company_growth"]["goals"]))
        self.assertTrue(economy.audit_world(self.w))

if __name__ == "__main__":
    unittest.main()