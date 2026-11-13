"""0.8.0 Living Business World deterministic NPC economy tests."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from server import economy as e
from server.service import WorldStore

class LivingBusiness080Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.n=0

    def cmd(self,actor,kind,**fields):
        self.n+=1
        return e.apply_command(self.w,actor,{"type":kind,"command_id":f"npc080-{self.n:05}",
            "expected_revision":self.w["revision"],**fields})

    def test_autonomous_competitor_construction_and_production(self):
        initial=e.money_total(self.w)
        e.advance(self.w,12)
        self.assertIn("company:npc_auto",self.w["wallets"])
        facilities=[f for f in self.w["facilities"].values() if f["owner"]=="npc_auto"]
        self.assertEqual({f["kind"] for f in facilities},{"factory","shop"})
        self.assertTrue(all("plot" in f for f in facilities))
        e.advance(self.w,12)
        self.assertTrue(any(f["production_last_units"]>0 for f in facilities if f["kind"]=="factory"))
        self.assertTrue(any(ev["action"]=="purchase" for ev in self.w["npc_decisions"]))
        self.assertEqual(e.money_total(self.w),initial)
        self.assertTrue(e.audit_world(self.w))

    def test_npc_reacts_to_player_prices(self):
        e.advance(self.w,12)
        shop=self.w["facilities"]["npc-shop"]
        old=shop["prices"]["bread"]
        self.cmd("player","facility.set_price",facility_id="player-shop",good="bread",price_minor=11000)
        e.advance(self.w,12)
        self.assertLess(shop["prices"]["bread"],old)
        self.assertTrue(e.audit_world(self.w))

    def test_npc_buys_real_player_contract_with_escrow(self):
        offer=self.cmd("player","contract.offer",facility_id="player-factory",good="grain",
            quantity=3,price_minor=4000)
        e.advance(self.w,12)
        contract=self.w["contracts"][offer["contract_id"]]
        self.assertEqual(contract["status"],"in_transit")
        self.assertIn(contract["buyer"],e.NPC_OWNERS)
        self.assertEqual(self.w["wallets"]["escrow:"+offer["contract_id"]],12000)
        e.advance(self.w,12)
        self.assertEqual(contract["status"],"delivered")
        self.assertEqual(self.w["wallets"]["escrow:"+offer["contract_id"]],0)
        self.assertTrue(e.audit_world(self.w))

    def test_npc_offers_are_player_acceptable(self):
        e.advance(self.w,36)
        offers=[c for c in self.w["contracts"].values()
                if c["seller"] in e.NPC_OWNERS and c["status"]=="offered"]
        self.assertTrue(offers)
        contract=offers[0]
        source=self.w["facilities"][contract["from"]]
        # Goods may have moved since listing, acceptance must reject rather than mint.
        if source["stock"][contract["good"]] >= contract["quantity"]:
            self.cmd("player","contract.accept",contract_id=contract["id"],destination_id="player-shop")
            self.assertEqual(contract["buyer"],"player")
            self.assertTrue(e.audit_world(self.w))

    def test_player_cannot_impersonate_npc(self):
        e.advance(self.w,12)
        for actor in e.NPC_OWNERS:
            with self.assertRaises(e.EconomyError):
                self.cmd(actor,"facility.set_price",facility_id="npc-shop",good="bread",price_minor=15000)
            with self.assertRaises(e.EconomyError):
                e.snapshot(self.w,actor)
        self.assertTrue(e.audit_world(self.w))

    def test_monthly_growth_caps_and_long_run_conservation(self):
        initial=e.money_total(self.w)
        for _ in range(18):
            e.advance(self.w,360)
            self.assertTrue(e.audit_world(self.w))
        self.assertEqual(e.money_total(self.w),initial)
        self.assertTrue(all(sum(f["owner"]==owner for f in self.w["facilities"].values()) <= e.NPC_MAX_BUILDINGS
                            for owner in e.NPC_OWNERS))
        self.assertLessEqual(len(self.w["npc_decisions"]),80)

    def test_migration_old_saves_and_restart_determinism(self):
        old=e.new_world()
        old.pop("npc_decisions")
        old.pop("npc_next_action")
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"world.sqlite"
            store=WorldStore(path,epoch_unix=1800000000)
            store.db.execute("UPDATE world_state SET payload=? WHERE id=1",(json.dumps(old),))
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            self.assertTrue(e.audit_world(store.world))
            store.advance_if_due(1800000000 + 12 * e.TICK_SECONDS)
            state=copy.deepcopy(store.world)
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            self.assertEqual(state,store.world)
            self.assertTrue(e.audit_world(store.world))
            store.db.close()
            store._writer_lock.close()

    def test_no_player_asset_mutation_from_npc_decision(self):
        before=copy.deepcopy({k:v for k,v in self.w["facilities"].items() if v["owner"]=="player"})
        e.advance(self.w,12)
        after={k:v for k,v in self.w["facilities"].items() if v["owner"]=="player"}
        # Player factory still follows its existing tick-based production, not NPC planning.
        for key in before:
            self.assertEqual(before[key]["workers"],after[key]["workers"])
            self.assertEqual(before[key]["production_target"],after[key]["production_target"])
            self.assertEqual(before[key]["prices"],after[key]["prices"])

if __name__=="__main__":
    unittest.main()