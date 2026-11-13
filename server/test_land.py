import copy
import json
import tempfile
import unittest
from pathlib import Path
from server import economy as econ, land
from server.service import WorldStore


class SpatialLandTests(unittest.TestCase):
    def setUp(self):
        self.w=econ.new_world()
        self.seq=0

    def issue(self, command_type, actor="player", **fields):
        self.seq+=1
        return econ.apply_command(self.w,actor,{"type":command_type,"command_id":f"land-test-{self.seq:04}",
                     "expected_revision":self.w["revision"],**fields})

    def available(self, ore=False, edge=False):
        layout=self.w["land"]["ufa"]
        for y in range(32):
            for x in range(32):
                if edge and x != 31: continue
                if land.code_at("ufa",x,y)==0 and land.key(x,y) not in layout["plots"] and (not ore or land.has_ore("ufa",x,y)):
                    return x,y
        raise AssertionError("no fixture")

    def test_terrain_and_expansion_stability(self):
        chunks=land.initial_chunks()
        first=[land.code_at("ufa",x,y) for y in range(64) for x in range(64)]
        self.assertTrue(land.grow("ufa",chunks,{},31,1))
        self.assertIn("2:0",chunks)
        self.assertFalse(land.grow("ufa",chunks,{},31,1))
        self.assertEqual(first,[land.code_at("ufa",x,y) for y in range(64) for x in range(64)])
        self.assertEqual(land.code_at("ufa",34,2),0)

    def test_buy_build_expand_idempotency(self):
        x,y=self.available(edge=True)
        self.issue("land.buy",city="ufa",x=x,y=y)
        command={"type":"facility.build","command_id":"spatial-repeat-001",
                 "expected_revision":self.w["revision"],"city":"ufa","kind":"shop","x":x,"y":y}
        result=econ.apply_command(self.w,"player",command)
        self.assertTrue(result["expanded"])
        self.assertEqual(result,econ.apply_command(self.w,"player",command))
        self.assertTrue(econ.audit_world(self.w))
        self.assertEqual(self.w["facilities"][result["facility_id"]]["plot"],{"x":x,"y":y})
        self.assertIn("2:0",self.w["land"]["ufa"]["chunks"])

    def test_invalid_purchase_build_ownership_and_resource(self):
        before=copy.deepcopy(self.w)
        for x,y in [(0,0),(-1,1),(100,100),(True,1),(1.0,1)]:
            with self.assertRaises(econ.EconomyError):self.issue("land.buy",city="ufa",x=x,y=y)
            self.assertEqual(before,self.w)
        x,y=self.available()
        self.issue("land.buy",city="ufa",x=x,y=y)
        after=copy.deepcopy(self.w)
        with self.assertRaises(econ.EconomyError):self.issue("land.buy",city="ufa",x=x,y=y)
        with self.assertRaises(econ.EconomyError):self.issue("facility.build",actor="rival",city="ufa",kind="factory",x=x,y=y)
        self.assertEqual(after,self.w)
        if not land.has_ore("ufa",x,y):
            with self.assertRaises(econ.EconomyError):self.issue("facility.build",city="ufa",kind="mine",x=x,y=y)
            self.assertEqual(after,self.w)

    def test_all_standalone_types_and_cash(self):
        for kind in ["shop","factory","warehouse","mine","research_center","car_dealership"]:
            w=econ.new_world()
            layout=w["land"]["ufa"]
            x,y=land.free_plot("ufa",layout["chunks"],layout["plots"],kind=="mine")
            before=econ.money_total(w)
            econ.apply_command(w,"player",{"type":"land.buy","command_id":"buy-spatial-001",
                "expected_revision":w["revision"],"city":"ufa","x":x,"y":y})
            result=econ.apply_command(w,"player",{"type":"facility.build","command_id":"build-spatial-001",
                "expected_revision":w["revision"],"city":"ufa","kind":kind,"x":x,"y":y})
            f=w["facilities"][result["facility_id"]]
            self.assertEqual(f["kind"],kind)
            self.assertEqual(before,econ.money_total(w))
            self.assertTrue(econ.audit_world(w))
            cash=w["wallets"]["company:player"]
            with self.assertRaises(econ.EconomyError):
                econ.apply_command(w,"player",{"type":"facility.build","command_id":"build-spatial-002",
                "expected_revision":w["revision"],"city":"ufa","kind":kind,"x":x,"y":y})
            self.assertEqual(cash,w["wallets"]["company:player"])

    def test_migration_and_db_restart(self):
        old=econ.new_world()
        old.pop("land")
        for f in old["facilities"].values():f.pop("plot")
        wallets=copy.deepcopy(old["wallets"])
        econ.land.ensure_world(old)
        self.assertEqual(wallets,old["wallets"])
        self.assertTrue(econ.audit_world(old))
        duplicate=copy.deepcopy(old)
        econ.land.ensure_world(old)
        self.assertEqual(old,duplicate)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/"world.db"
            store=WorldStore(path,epoch_unix=1800000000)
            snap=store.snapshot("player")
            x,y=land.free_plot("ufa",snap["land"]["ufa"]["chunks"],snap["land"]["ufa"]["plots"])
            store.issue("player",{"type":"land.buy","command_id":"land-db-persist-1",
                "expected_revision":snap["revision"],"city":"ufa","x":x,"y":y})
            layout=copy.deepcopy(store.world["land"])
            store.close()
            reopened=WorldStore(path)
            self.assertEqual(layout,reopened.world["land"])
            reopened.close()


if __name__=="__main__":unittest.main(verbosity=2)
