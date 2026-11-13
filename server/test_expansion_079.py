"""0.7.9 industrial and escrowed player-to-player contract regressions."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from server import economy as e
from server.service import WorldStore

class Expansion079Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.n=0
    def cmd(self,actor,kind,**kwargs):
        self.n+=1
        return e.apply_command(self.w,actor,{"type":kind,"command_id":f"expansion-079-{self.n:04}",
            "expected_revision":self.w["revision"],**kwargs})

    def test_mine_steel_parts_car_chain(self):
        mine=e._facility("player","beloretsk","mine","test-mine")
        mine["plot"]={"x":1,"y":1}
        self.w["facilities"][mine["id"]]=mine
        factory=e._facility("player","beloretsk","factory","test-plant")
        self.w["facilities"][factory["id"]]=factory
        initial=e.money_total(self.w)
        e.advance(self.w,6)
        self.assertGreater(mine["stock"]["ore"],0)
        self.assertEqual(e.money_total(self.w),initial)
        self.cmd("player","shipment.create",facility_id="test-mine",destination_id="test-plant",good="ore",quantity=8)
        e.advance(self.w,1)
        self.cmd("player","facility.set_recipe",facility_id="test-plant",recipe="steel")
        e.advance(self.w,1)
        self.assertGreater(factory["stock"]["steel"],0)
        self.cmd("player","facility.upgrade_equipment",facility_id="test-plant")
        self.cmd("player","facility.set_staff",facility_id="test-plant",workers=8,wage_minor=750)
        self.cmd("player","facility.set_production",facility_id="test-plant",target=2)
        e.advance(self.w,1)
        self.cmd("player","facility.set_recipe",facility_id="test-plant",recipe="parts")
        e.advance(self.w,1)
        self.assertGreater(factory["stock"]["parts"],0)
        self.cmd("player","facility.upgrade_equipment",facility_id="test-plant")
        self.cmd("player","facility.set_recipe",facility_id="test-plant",recipe="car")
        e.advance(self.w,1)
        self.assertGreater(factory["stock"]["car"],0)
        for good in e.GOODS:
            a=self.w["audit"][good]
            self.assertEqual(e.goods_total(self.w)[good],a["initial"]+a["sourced"]+a["converted_out"]-a["converted_in"]-a["consumed"])
        self.assertEqual(e.money_total(self.w),initial)

    def test_escrow_contract_delivers_and_settles(self):
        source="player-factory"
        dest="rival-shop"
        offer=self.cmd("player","contract.offer",facility_id=source,good="grain",quantity=5,price_minor=8000)
        cid=offer["contract_id"]
        seller_before=self.w["wallets"]["company:player"]
        buyer_before=self.w["wallets"]["company:rival"]
        receipt=self.cmd("rival","contract.accept",contract_id=cid,destination_id=dest)
        self.assertEqual(self.w["wallets"]["escrow:"+cid],40000)
        self.assertEqual(self.w["wallets"]["company:player"],seller_before)
        self.assertLess(self.w["wallets"]["company:rival"],buyer_before)
        self.assertEqual(self.w["contracts"][cid]["status"],"in_transit")
        self.assertTrue(e.audit_world(self.w))
        e.advance(self.w,receipt["eta_tick"]-self.w["tick"])
        self.assertEqual(self.w["contracts"][cid]["status"],"delivered")
        self.assertEqual(self.w["wallets"]["escrow:"+cid],0)
        self.assertTrue(any(x["kind"] == "contract.settlement" and x["amount"] == 40000 and x["credit"] == "company:player" for x in self.w["finance_history"]))
        self.assertGreater(self.w["facilities"][dest]["stock"]["grain"],0)
        self.assertTrue(e.audit_world(self.w))

    def test_contract_permission_and_idempotency(self):
        offer=self.cmd("player","contract.offer",facility_id="player-factory",good="grain",quantity=4,price_minor=7000)
        cid=offer["contract_id"]
        self.assertIn(cid,[x["id"] for x in e.snapshot(self.w,"rival")["contracts"]])
        for actor,dest in [("player","player-shop"),("rival","player-shop")]:
            before=copy.deepcopy(self.w)
            with self.assertRaises(e.EconomyError):
                self.cmd(actor,"contract.accept",contract_id=cid,destination_id=dest)
            self.assertEqual(before,self.w)
        self.cmd("rival","contract.accept",contract_id=cid,destination_id="rival-shop")
        before=copy.deepcopy(self.w)
        with self.assertRaises(e.EconomyError):
            self.cmd("rival","contract.accept",contract_id=cid,destination_id="rival-shop")
        self.assertEqual(before,self.w)

    def test_contract_offer_limits(self):
        before=copy.deepcopy(self.w)
        with self.assertRaises(e.EconomyError):
            self.cmd("player","contract.offer",facility_id="rival-factory",good="grain",quantity=5,price_minor=1000)
        self.assertEqual(before,self.w)
        for value in [0,-1,True,51]:
            before=copy.deepcopy(self.w)
            with self.assertRaises(e.EconomyError):
                self.cmd("player","contract.offer",facility_id="player-factory",good="grain",quantity=value,price_minor=1000)
            self.assertEqual(before,self.w)

    def test_warehouse_expansion_and_permissions(self):
        warehouse=e._facility("player","ufa","warehouse","player-warehouse")
        self.w["facilities"][warehouse["id"]]=warehouse
        first=self.cmd("player","facility.expand_storage",facility_id=warehouse["id"])
        self.assertEqual(first["capacity"],400)
        self.assertEqual(warehouse["storage_level"],1)
        self.assertTrue(e.audit_world(self.w))
        before=copy.deepcopy(self.w)
        with self.assertRaises(e.EconomyError):
            self.cmd("rival","facility.expand_storage",facility_id=warehouse["id"])
        self.assertEqual(self.w,before)
        with self.assertRaises(e.EconomyError):
            self.cmd("player","facility.expand_storage",facility_id="player-factory")

    def test_contract_persistence_and_escrow(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"world.sqlite"
            store=WorldStore(path,epoch_unix=1800000000)
            def issue(actor,kind,**fields):
                return store.issue(actor,dict(type=kind,command_id="persist-079-"+str(store.world["revision"]),
                    expected_revision=store.world["revision"],**fields))
            offer=issue("player","contract.offer",facility_id="player-factory",
                good="grain",quantity=3,price_minor=8000)
            ident=offer["contract_id"]
            issue("rival","contract.accept",contract_id=ident,destination_id="rival-shop")
            store.db.close()
            store._writer_lock.close()
            reopened=WorldStore(path)
            self.assertEqual(reopened.world["wallets"]["escrow:"+ident],24000)
            self.assertTrue(e.audit_world(reopened.world))
            self.assertIn(ident,[c["id"] for c in reopened.snapshot("rival")["contracts"]])
            reopened.db.close()
            reopened._writer_lock.close()

    def test_old_save_migration(self):
        old=e.new_world()
        for good in e.INDUSTRIAL_GOODS:
            old["audit"].pop(good)
            for fac in old["facilities"].values():
                fac["stock"].pop(good)
                fac["basis"].pop(good)
            for supplier in old["suppliers"].values():
                supplier.pop(good,None)
        old.pop("contracts")
        old.pop("next_contract")
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"world.sqlite"
            store=WorldStore(path,epoch_unix=1800000000)
            store.db.execute("UPDATE world_state SET payload=? WHERE id=1",(json.dumps(old),))
            store.db.close()
            store._writer_lock.close()
            reopened=WorldStore(path)
            self.assertTrue(e.audit_world(reopened.world))
            self.assertEqual(reopened.world["contracts"],{})
            self.assertEqual(reopened.world["facilities"]["player-factory"]["stock"]["ore"],0)
            reopened.db.close()
            reopened._writer_lock.close()

    def test_long_run_and_contract_stability(self):
        offer=self.cmd("player","contract.offer",facility_id="player-factory",good="grain",quantity=2,price_minor=9000)
        self.cmd("rival","contract.accept",contract_id=offer["contract_id"],destination_id="rival-shop")
        initial=e.money_total(self.w)
        for _ in range(15):
            e.advance(self.w,24)
        self.assertEqual(e.money_total(self.w),initial)
        self.assertTrue(e.audit_world(self.w))
        self.assertEqual(self.w["contracts"][offer["contract_id"]]["status"],"delivered")

if __name__=="__main__":
    unittest.main()