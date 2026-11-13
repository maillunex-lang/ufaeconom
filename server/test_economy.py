"""0.6 deterministic economy regression and long-run balance tests."""
from __future__ import annotations

import copy
import unittest

try:
    from server import economy as econ
except ModuleNotFoundError:
    import economy as econ


class Economy06Tests(unittest.TestCase):
    def setUp(self) -> None:
        self.w = econ.new_world()
        self.assertTrue(econ.audit_world(self.w))

    def issue(self, command_id: str, command_type: str, **kwargs) -> dict:
        return econ.apply_command(self.w, "player", {
            "command_id": command_id,
            "expected_revision": self.w["revision"],
            "type": command_type,
            **kwargs,
        })

    def test_npc_reacts_to_visible_competitor_prices(self) -> None:
        self.issue("offer-npc-001", "facility.set_price",
                   facility_id="player-shop", good="bread", price_minor=12000)
        old = self.w["facilities"]["npc-shop"]["prices"]["bread"]
        econ.advance(self.w, econ.TICKS_PER_DAY)
        new = self.w["facilities"]["npc-shop"]["prices"]["bread"]
        self.assertLess(new, old)
        self.assertGreaterEqual(new, econ.BASE_PRICES["bread"] * 7 // 10)
        self.assertTrue(econ.audit_world(self.w))

    def test_price_distance_ownership_competition(self) -> None:
        econ.advance(self.w)
        self.assertIn("npc-shop:bread", self.w["last_sales"])
        player_price = self.issue("offer-0001", "facility.set_price",
                                  facility_id="player-shop", good="bread",
                                  price_minor=12000)
        self.assertEqual(player_price["price_minor"], 12000)
        econ.advance(self.w)
        self.assertIn("player-shop:bread", self.w["last_sales"])
        with self.assertRaises(econ.EconomyError):
            self.issue("offer-0002", "facility.set_price",
                       facility_id="npc-shop", good="bread", price_minor=10000)
        self.assertTrue(econ.audit_world(self.w))

    def test_paid_shipments_cost_and_recovery(self) -> None:
        initial = econ.money_total(self.w)
        destination = self.w["facilities"]["player-sterlitamak"]
        source = self.w["facilities"]["player-shop"]
        source_before = source["stock"]["bread"]
        cmd = {"command_id": "freight-0001", "expected_revision": self.w["revision"],
               "type": "shipment.create", "facility_id": "player-shop",
               "destination_id": "player-sterlitamak", "good": "bread",
               "quantity": 10}
        result = econ.apply_command(self.w, "player", cmd)
        self.assertTrue(result["fee_minor"] > 0)
        self.assertEqual(source["stock"]["bread"], source_before - 10)
        self.assertEqual(len(self.w["shipments"]), 1)
        self.assertEqual(econ.apply_command(self.w, "player", cmd), result)
        self.assertEqual(len(self.w["shipments"]), 1)
        # Delivery is not instantaneous; it occurs on the assigned tick.
        elapsed = result["eta_tick"] - self.w["tick"]
        econ.advance(self.w, elapsed)
        self.assertFalse(self.w["shipments"])
        self.assertGreaterEqual(self.w["stats"]["delivered"], 10)
        self.assertGreaterEqual(destination["stock"]["bread"], 0)
        self.assertEqual(econ.money_total(self.w), initial)
        self.assertTrue(econ.audit_world(self.w))

    def test_unauthorized_malformed_and_capacity(self) -> None:
        for invalid in [
            ("illegal-0001", "facility.set_price", {
                "facility_id": "npc-shop", "good": "bread", "price_minor": 15500}),
            ("illegal-0002", "facility.set_price", {
                "facility_id": "player-shop", "good": "bread", "price_minor": -1}),
            ("illegal-0003", "shipment.create", {
                "facility_id": "player-shop", "destination_id": "npc-shop",
                "good": "bread", "quantity": 10}),
            ("illegal-0004", "shipment.create", {
                "facility_id": "player-shop", "destination_id": "player-sterlitamak",
                "good": "bread", "quantity": 1000}),
        ]:
            with self.subTest(command=invalid[0]), self.assertRaises(econ.EconomyError):
                self.issue(invalid[0], invalid[1], **invalid[2])
        self.assertTrue(econ.audit_world(self.w))

    def test_distance_affects_equal_price_shops(self) -> None:
        self.w["facilities"]["player-shop"]["prices"]["bread"] = 15000
        self.w["facilities"]["npc-shop"]["prices"]["bread"] = 15000
        self.w["facilities"]["player-shop"]["reputation"] = 70
        self.w["facilities"]["npc-shop"]["reputation"] = 70
        self.w["facilities"]["player-shop"]["customer_distance_km"] = 2
        self.w["facilities"]["npc-shop"]["customer_distance_km"] = 25
        econ.advance(self.w)
        self.assertIn("player-shop:bread", self.w["last_sales"])
        self.assertTrue(econ.audit_world(self.w))

    def test_rejected_purchase_is_transactionally_clean(self) -> None:
        before = econ.copy_world(self.w)
        with self.assertRaises(econ.EconomyError):
            self.issue("unfilled-0001", "facility.buy",
                       facility_id="player-shop", good="grain", quantity=99)
        self.assertEqual(self.w, before)

    def test_two_player_companies_have_separate_ownership(self) -> None:
        self.assertIn("company:rival", self.w["wallets"])
        self.assertTrue(self.w["facilities"]["rival-shop"]["owner"] == "rival")
        with self.assertRaises(econ.EconomyError):
            self.issue("steal-00001", "facility.set_price",
                       facility_id="rival-shop", good="bread", price_minor=12000)
        before = econ.money_total(self.w)
        result = econ.apply_command(self.w, "rival", {
            "command_id": "rival-0001", "expected_revision": self.w["revision"],
            "type": "facility.set_price", "facility_id": "rival-shop",
            "good": "bread", "price_minor": 14000,
        })
        self.assertTrue(result["ok"])
        self.assertEqual(self.w["facilities"]["rival-shop"]["prices"]["bread"], 14000)
        self.assertEqual(econ.money_total(self.w), before)
        self.assertTrue(econ.audit_world(self.w))

    def test_separate_company_finances_build_and_budget(self) -> None:
        before = econ.money_total(self.w)
        result = self.issue("build-00001", "facility.build",
                            city="beloretsk", kind="warehouse")
        self.assertIn(result["facility_id"], self.w["facilities"])
        self.assertEqual(self.w["facilities"][result["facility_id"]]["owner"], "player")
        self.assertEqual(before, econ.money_total(self.w))
        self.assertTrue(econ.audit_world(self.w))

    def test_one_thousand_game_days_conservation_and_replay(self) -> None:
        second = econ.copy_world(self.w)
        # 12 microticks/game day: 12000 production and market ticks.
        for day in range(1000):
            econ.advance(self.w, econ.TICKS_PER_DAY)
            econ.advance(second, econ.TICKS_PER_DAY)
            if day % 30 == 0:
                self.assertTrue(econ.audit_world(self.w), f"audit day {day}")
                self.assertEqual(self.w["wallets"], second["wallets"])
                self.assertEqual(self.w["facilities"], second["facilities"])
                self.assertEqual(self.w["audit"], second["audit"])
                # Persistence layer will flush these into durable ledger rows.
                self.w["pending_ledger"].clear()
                second["pending_ledger"].clear()
        self.assertEqual(self.w["tick"], 12000)
        self.assertTrue(econ.audit_world(self.w))
        self.assertEqual(self.w["wallets"], second["wallets"])
        self.assertGreater(self.w["stats"]["produced"], 0)
        self.assertGreater(self.w["stats"]["units_sold"], 0)
        self.assertGreaterEqual(self.w["company_metrics"]["player"]["revenue"], 0)
        self.assertGreaterEqual(self.w["company_metrics"]["npc"]["freight"], 0)
        self.assertGreaterEqual(self.w["stats"]["blocked"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
