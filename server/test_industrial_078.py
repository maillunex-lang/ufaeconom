"""0.7.8 production chains, equipment, trading, logistics, save migration."""
import copy
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from server import economy as e
from server.service import WorldStore

class Industrial078Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.n=0

    def cmd(self,kind, actor="player", **args):
        self.n+=1
        return e.apply_command(self.w,actor,{"type":kind,"command_id":f"industrial-078-{self.n:04}",
            "expected_revision":self.w["revision"],**args})

    def test_two_step_chain_and_inventory_conservation(self):
        factory=e._facility("player", "beloretsk", "factory", "isolated-factory")
        self.w["facilities"]["isolated-factory"]=factory
        self.cmd("facility.buy",facility_id="isolated-factory",good="grain",quantity=5)
        self.cmd("facility.set_recipe",facility_id="isolated-factory",recipe="flour")
        e.advance(self.w)
        self.assertEqual(factory["stock"]["flour"],2)
        self.cmd("facility.set_recipe",facility_id="isolated-factory",recipe="bakery")
        e.advance(self.w)
        self.assertEqual(factory["stock"]["flour"],1)
        self.assertEqual(factory["production_last_units"],3)
        self.assertTrue(e.audit_world(self.w))

    def test_equipment_upgrade_capex_and_energy_savings(self):
        factory=self.w["facilities"]["player-factory"]
        before=e.money_total(self.w)
        capex=self.w["company_metrics"]["player"]["capital_expenditure"]
        result=self.cmd("facility.upgrade_equipment",facility_id="player-factory")
        self.assertEqual(result["equipment_level"],2)
        self.assertEqual(self.w["company_metrics"]["player"]["capital_expenditure"]-capex,2_000_000)
        self.assertEqual(e.money_total(self.w),before)
        e.advance(self.w)
        self.assertTrue(e.audit_world(self.w))
        self.cmd("facility.upgrade_equipment",facility_id="player-factory")
        with self.assertRaises(e.EconomyError):
            self.cmd("facility.upgrade_equipment",facility_id="player-factory")
        self.assertEqual(factory["equipment_level"],3)

    def test_flour_retail_and_shipping(self):
        factory=e._facility("player", "beloretsk", "factory", "isolated-factory")
        self.w["facilities"]["isolated-factory"]=factory
        self.cmd("facility.buy",facility_id="isolated-factory",good="grain",quantity=5)
        self.cmd("facility.set_recipe",facility_id="isolated-factory",recipe="flour")
        e.advance(self.w,3)
        self.cmd("facility.set_price",facility_id="player-shop",good="flour",price_minor=8000)
        result=self.cmd("shipment.create",facility_id="isolated-factory",destination_id="player-shop",good="flour",quantity=3)
        self.assertGreater(result["fee_minor"],0)
        e.advance(self.w,result["eta_tick"]-self.w["tick"])
        self.assertTrue(e.audit_world(self.w))
        self.assertGreater(self.w["facilities"]["player-shop"]["stock"]["flour"],0)

    def test_rejected_recipe_and_equipment_are_atomic(self):
        for kind, fields in [
            ("facility.set_recipe",{"facility_id":"rival-factory","recipe":"flour"}),
            ("facility.set_recipe",{"facility_id":"player-factory","recipe":"invalid"}),
            ("facility.set_recipe",{"facility_id":"player-shop","recipe":"flour"}),
            ("facility.upgrade_equipment",{"facility_id":"rival-factory"}),
            ("facility.set_price",{"facility_id":"player-shop","good":"flour","price_minor":0}),
        ]:
            original=copy.deepcopy(self.w)
            with self.assertRaises(e.EconomyError):
                self.cmd(kind,**fields)
            self.assertEqual(original,self.w)

    def test_legacy_saved_world_migrates(self):
        old=e.new_world()
        for fac in old["facilities"].values():
            fac["stock"].pop("flour")
            fac["basis"].pop("flour")
            fac["prices"].pop("flour")
            fac.pop("recipe")
            fac.pop("equipment_level")
        for market in old["suppliers"].values():
            market.pop("flour", None)
        old["audit"].pop("flour")
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"game.sqlite"
            store=WorldStore(path,epoch_unix=1800000000)
            store.db.execute("UPDATE world_state SET payload=? WHERE id=1",(json.dumps(old),))
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            self.assertTrue(e.audit_world(store.world))
            self.assertIn("flour",store.world["facilities"]["player-factory"]["stock"])
            store.issue("player",{"type":"facility.set_recipe","command_id":"migration-078","expected_revision":store.world["revision"],"facility_id":"player-factory","recipe":"flour"})
            store.db.close()
            store._writer_lock.close()
            store=WorldStore(path)
            self.assertEqual(store.snapshot("player")["facilities"]["player-factory"]["recipe"],"flour")
            store.db.close()
            store._writer_lock.close()

    def test_long_run_conservation(self):
        self.cmd("facility.set_recipe",facility_id="player-factory",recipe="flour")
        self.cmd("facility.set_staff",facility_id="player-factory",workers=12,wage_minor=900)
        self.cmd("facility.set_production",facility_id="player-factory",target=3)
        money=e.money_total(self.w)
        for _ in range(20):
            e.advance(self.w,18)
        self.assertEqual(e.money_total(self.w),money)
        self.assertTrue(e.audit_world(self.w))

if __name__=="__main__":
    unittest.main()