"""0.8.1 market strategy, competition, demand, share and persistence."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from server import economy as e
from server.service import WorldStore

class Market081Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.initial=e.money_total(self.w)
    def test_strategy_identity_and_player_visibility(self):
        e.advance(self.w,12)
        data=e.snapshot(self.w,"player")
        strategies={n["owner"]:n["strategy"] for n in data["npc_competitors"]}
        self.assertEqual(strategies,e.NPC_STRATEGIES)
        self.assertEqual(data["market_window_days"],1)
        self.assertEqual(data["market_analytics"],e.market_report(self.w))
        self.assertTrue(e.audit_world(self.w))
    def test_real_market_share_not_estimated(self):
        e.advance(self.w,12)
        report=e.market_report(self.w)
        self.assertGreater(report["ufa"]["bread"]["units_sold_30d"],0)
        shares=report["ufa"]["bread"]["share_bps"]
        self.assertTrue(shares)
        self.assertLessEqual(sum(shares.values()),10000)
        self.assertGreaterEqual(sum(shares.values()),9998)
        self.assertEqual(report["beloretsk"]["bread"]["units_sold_30d"],0)
        self.assertEqual(report["beloretsk"]["bread"]["share_bps"],{})
    def test_competing_strategies_change_prices_differently(self):
        e.advance(self.w,12)
        shop1=self.w["facilities"]["npc-shop"]
        shop2=next(f for f in self.w["facilities"].values()
                   if f["owner"]=="npc_auto" and f["kind"]=="shop")
        shop2["city"]="ufa"
        shop2["stock"]["bread"]=20
        self.w["audit"]["bread"]["sourced"]+=20
        self.w["facilities"]["player-shop"]["stock"]["bread"]=20
        self.w["facilities"]["player-shop"]["prices"]["bread"]=11000
        old1=shop1["prices"]["bread"]
        old2=shop2["prices"]["bread"]
        e._npc_decide(self.w)
        self.assertLessEqual(shop1["prices"]["bread"],old1)
        self.assertGreaterEqual(shop2["prices"]["bread"],old2-200)
        self.assertNotEqual(shop1["prices"]["bread"],shop2["prices"]["bread"])
    def test_growth_selects_cities_from_demand_and_budget(self):
        e.advance(self.w,360)
        for owner in e.NPC_OWNERS:
            self.assertTrue(any(ev["action"]=="expansion.strategy" and ev["owner"]==owner
                                for ev in self.w["npc_decisions"]))
        self.assertTrue(e.audit_world(self.w))
        self.assertEqual(e.money_total(self.w),self.initial)
    def test_rolling_market_window_bounded(self):
        for _ in range(35):
            e.advance(self.w,12)
        self.assertEqual(len(self.w["market_daily"]),30)
        self.assertEqual(e.snapshot(self.w,"player")["market_window_days"],30)
        self.assertTrue(e.audit_world(self.w))
    def test_market_data_migrates_and_survives_restart(self):
        old=e.new_world()
        for key in ("market_daily","market_today","market_totals"):
            old.pop(key,None)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/"market.sqlite"
            store=WorldStore(path,epoch_unix=1800000000)
            store.db.execute("UPDATE world_state SET payload=? WHERE id=1",(json.dumps(old),))
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            store.advance_if_due(1800000000+24*e.TICK_SECONDS)
            report=store.snapshot("player")["market_analytics"]
            self.assertGreater(report["ufa"]["bread"]["units_sold_30d"],0)
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            self.assertEqual(store.snapshot("player")["market_analytics"],report)
            self.assertTrue(e.audit_world(store.world))
            store.db.close()
            store._writer_lock.close()
    def test_determinism_and_long_run_conservation(self):
        first=e.new_world()
        second=copy.deepcopy(first)
        for _ in range(6):
            e.advance(first,360)
            e.advance(second,360)
        self.assertEqual(first,second)
        self.assertTrue(e.audit_world(first))
        self.assertEqual(e.money_total(first),e.money_total(second))
        self.assertEqual(e.money_total(first),self.initial)

if __name__=="__main__":
    unittest.main()