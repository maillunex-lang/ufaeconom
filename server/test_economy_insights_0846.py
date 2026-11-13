from __future__ import annotations
import unittest
from server import economy

class EconomyInsightsTests(unittest.TestCase):
    def setUp(self):
        self.world = economy.new_world()
    def test_factory_plan_and_shortage(self):
        info = economy.company_operations(self.world, "player")
        factory = next(x for x in info["factory_diagnostics"] if x["id"] == "player-factory")
        self.assertEqual(factory["planned_batches"], 1)
        self.assertEqual(factory["potential_output"], 2)
        self.world["facilities"]["player-factory"]["stock"]["grain"] = 0
        factory = economy.company_operations(self.world, "player")["factory_diagnostics"][0]
        self.assertIn("raw_shortage", factory["issues"])
        self.assertEqual(factory["potential_output"], 0)
    def test_equipment_staff_and_paused(self):
        f = self.world["facilities"]["player-factory"]
        f["recipe"] = "car"
        self.assertIn("equipment", economy.company_operations(self.world, "player")["factory_diagnostics"][0]["issues"])
        f["workers"] = 0
        f["production_target"] = 0
        issues = economy.company_operations(self.world, "player")["factory_diagnostics"][0]["issues"]
        self.assertIn("no_staff", issues)
        self.assertIn("paused", issues)
    def test_competitor_prices_are_scoped_and_read_only(self):
        before = economy.copy_world(self.world)
        offers = economy.competition_opportunities(self.world, "player")
        self.assertTrue(any(o["facility_id"] == "player-shop" for o in offers))
        self.assertTrue(all(o["facility_id"] != "rival-shop" for o in offers))
        for offer in offers:
            self.assertEqual(offer["difference_minor"], offer["own_price_minor"]-offer["lowest_competitor_minor"])
        self.assertEqual(self.world, before)
    def test_snapshot_is_scoped(self):
        own = economy.snapshot(self.world, "player")
        rival = economy.snapshot(self.world, "rival")
        self.assertTrue(own["company_operations"]["facility_count"] > 0)
        self.assertTrue(all(item["id"].startswith("player-") for item in own["company_operations"]["factory_diagnostics"]))
        self.assertTrue(all(item["id"].startswith("rival-") for item in rival["company_operations"]["factory_diagnostics"]))
        self.assertTrue(economy.audit_world(self.world))

if __name__ == "__main__":
    unittest.main()