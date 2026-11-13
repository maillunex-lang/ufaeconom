"""0.8.2 server-authoritative read-only economic intelligence."""
import copy
import unittest
from server import economy as e

class Intelligence082Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
    def test_empty_history_is_explicitly_limited(self):
        d=e.economic_intelligence(self.w,"player")
        self.assertEqual(d["forecast_horizon_days"],1)
        self.assertEqual(d["forecasts"]["ufa"]["bread"]["forecast_daily_units"],0)
        self.assertEqual(d["forecasts"]["ufa"]["bread"]["confidence"],"limited")
        self.assertIsNone(d["profitability"]["margin_bps"])
    def test_forecasts_use_actual_sales_not_fabricated(self):
        e.advance(self.w,12)
        report=e.economic_intelligence(self.w,"player")
        self.assertEqual(report["forecasts"]["ufa"]["bread"]["forecast_daily_units"],
                         e.market_report(self.w)["ufa"]["bread"]["units_sold_30d"])
        self.assertEqual(report["forecasts"]["beloretsk"]["bread"]["forecast_daily_units"],0)
        self.assertEqual(report["forecasts"]["ufa"]["bread"]["observed_days"],1)
    def test_procurement_respects_capacity_cash_and_supplier(self):
        fac=self.w["facilities"]["player-factory"]
        fac["stock"]["grain"]=0
        self.w["audit"]["grain"]["consumed"]+=60
        data=e.economic_intelligence(self.w,"player")
        plan=next(p for p in data["procurement_plans"] if p["facility_id"]=="player-factory")
        self.assertGreater(plan["shortage_units"],0)
        self.assertLessEqual(plan["recommended_buy_units"],fac["capacity"])
        self.assertEqual(plan["estimated_cost_minor"],
                         plan["recommended_buy_units"]*e.SOURCE_PRICES["grain"])
        self.w["wallets"]["company:player"]=0
        plan=e.economic_intelligence(self.w,"player")["procurement_plans"][0]
        self.assertEqual(plan["recommended_buy_units"],0)
    def test_snapshot_private_and_read_only(self):
        original=copy.deepcopy(self.w)
        report=e.snapshot(self.w,"player")["economic_intelligence"]
        self.assertEqual(self.w,original)
        self.assertEqual(report["profitability"]["basis"],"cumulative")
        self.assertTrue(all(p["facility_id"].startswith("player-") for p in report["procurement_plans"]))
        with self.assertRaises(e.EconomyError):
            e.economic_intelligence(self.w,"npc")
    def test_negative_margin_recommendation(self):
        self.w["company_metrics"]["player"]["revenue"]=1000
        self.w["company_metrics"]["player"]["profit"]=-200
        report=e.economic_intelligence(self.w,"player")
        self.assertEqual(report["profitability"]["margin_bps"],-2000)
        self.assertTrue(any(r["kind"]=="negative_margin" for r in report["recommendations"]))
    def test_rolling_history_and_determinism(self):
        a=e.new_world()
        b=copy.deepcopy(a)
        for _ in range(35):
            e.advance(a,12)
            e.advance(b,12)
        self.assertEqual(e.economic_intelligence(a,"player"),e.economic_intelligence(b,"player"))
        self.assertEqual(len(a["market_daily"]),30)
        self.assertEqual(e.economic_intelligence(a,"player")["forecasts"]["ufa"]["bread"]["observed_days"],7)
        self.assertTrue(e.audit_world(a))
        self.assertEqual(e.money_total(a),e.money_total(b))
if __name__=="__main__":
    unittest.main()