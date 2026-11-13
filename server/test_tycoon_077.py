"""Stage 0.7.7 authoritative tycoon regressions."""
import copy
import tempfile
import unittest
from pathlib import Path
from server import economy as e
from server.service import WorldStore

class Tycoon077Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.i=0

    def command(self, typ, actor="player", **fields):
        self.i+=1
        return e.apply_command(self.w,actor,dict(type=typ,command_id=f"tycoon-077-{self.i:04}",expected_revision=self.w["revision"],**fields))

    def test_staff_and_production_owner_checks(self):
        f=self.w["facilities"]["player-factory"]
        self.command("facility.set_staff",facility_id="player-factory",workers=12,wage_minor=900)
        self.command("facility.set_production",facility_id="player-factory",target=3)
        self.assertEqual(f["workers"],12)
        self.assertEqual(f["production_target"],3)
        before=e.money_total(self.w)
        e.advance(self.w)
        self.assertEqual(f["production_last_units"],6)
        self.assertEqual(e.money_total(self.w),before)
        self.assertTrue(e.audit_world(self.w))
        with self.assertRaises(e.EconomyError):
            self.command("facility.set_staff",facility_id="npc-factory",workers=10,wage_minor=750)
        with self.assertRaises(e.EconomyError):
            self.command("facility.set_production",facility_id="rival-factory",target=4)

    def test_invalid_commands_do_not_change_state(self):
        for kind, fields in [
            ("facility.set_staff",{"facility_id":"player-factory","workers":100,"wage_minor":750}),
            ("facility.set_staff",{"facility_id":"player-factory","workers":True,"wage_minor":750}),
            ("facility.set_staff",{"facility_id":"player-factory","workers":4,"wage_minor":0}),
            ("facility.set_production",{"facility_id":"player-shop","target":2}),
            ("facility.set_production",{"facility_id":"player-factory","target":True}),
            ("facility.set_production",{"facility_id":"player-factory","target":5}),
        ]:
            before=copy.deepcopy(self.w)
            with self.assertRaises(e.EconomyError):
                self.command(kind,**fields)
            self.assertEqual(self.w,before)

    def test_zero_workers_blocks_production(self):
        self.command("facility.set_staff",facility_id="player-factory",workers=0,wage_minor=750)
        e.advance(self.w)
        self.assertEqual(self.w["facilities"]["player-factory"]["production_last_units"],0)
        self.assertTrue(e.audit_world(self.w))

    def test_finance_history_private_and_bounded(self):
        self.command("facility.set_staff",facility_id="player-factory",workers=8,wage_minor=750)
        e.advance(self.w,20)
        player=e.snapshot(self.w,"player")
        rival=e.snapshot(self.w,"rival")
        self.assertTrue(player["finance_history"])
        self.assertTrue(all("company:rival" not in (x["debit"],x["credit"]) for x in player["finance_history"]))
        self.assertTrue(all("company:player" not in (x["debit"],x["credit"]) for x in rival["finance_history"]))
        self.assertLessEqual(len(self.w["finance_history"]),200)
        self.assertTrue(e.audit_world(self.w))

    def test_long_run_with_staff_and_retail_and_freight(self):
        self.command("facility.set_staff",facility_id="player-factory",workers=12,wage_minor=850)
        self.command("facility.set_production",facility_id="player-factory",target=3)
        self.command("facility.set_price",facility_id="player-shop",good="bread",price_minor=12000)
        initial=e.money_total(self.w)
        for _ in range(30):
            e.advance(self.w,12)
        self.assertEqual(e.money_total(self.w),initial)
        self.assertTrue(e.audit_world(self.w))
        self.assertGreater(self.w["company_metrics"]["player"]["revenue"],0)
        self.assertLessEqual(len(self.w["finance_history"]),200)

    def test_store_round_trip_and_idempotency(self):
        with tempfile.TemporaryDirectory() as tmp:
            store=WorldStore(Path(tmp)/"world.sqlite",epoch_unix=1800000000)
            command={"type":"facility.set_staff","command_id":"staff-077-idem","expected_revision":store.world["revision"],"facility_id":"player-factory","workers":8,"wage_minor":900}
            first=store.issue("player",command)
            self.assertEqual(store.issue("player",command),first)
            self.assertEqual(store.world["facilities"]["player-factory"]["workers"],8)
            self.assertTrue(e.audit_world(store.world))
            store.db.close()
            store._writer_lock.close()
            reopened=WorldStore(Path(tmp)/"world.sqlite")
            self.assertEqual(reopened.snapshot("player")["facilities"]["player-factory"]["workers"],8)
            reopened.db.close()
            reopened._writer_lock.close()

if __name__=="__main__":
    unittest.main()