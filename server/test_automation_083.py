"""0.8.3 automation budget, ownership, idempotency and server tick."""
import copy
import unittest
from server import economy as e

class Automation083Tests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.n=0
    def configure(self, facility="player-factory", **overrides):
        self.n+=1
        cmd={"type":"automation.configure","facility_id":facility,
             "command_id":f"automation083-{self.n:04}",
             "expected_revision":self.w["revision"],
             "enabled":True,"buy_inputs":True,"restock":False,"production":True,
             "pricing":False,"daily_budget_minor":50000,"stock_target":80,
             "max_purchase_units":20,"production_target":2,"undercut_minor":100}
        cmd.update(overrides)
        return e.apply_command(self.w,"player",cmd)
    def test_opt_in_and_budget(self):
        before=copy.deepcopy(self.w["automation_rules"])
        e.advance(self.w,12)
        self.assertEqual(before,self.w["automation_rules"])
        self.configure()
        e.advance(self.w,12)
        self.assertLessEqual(self.w["automation_spend"]["player-factory"],50000)
        self.assertEqual(self.w["facilities"]["player-factory"]["production_target"],2)
        self.assertTrue(any(ev["action"]=="buy" for ev in self.w["automation_events"]))
        self.assertTrue(e.audit_world(self.w))
    def test_reject_foreign_and_bad_config(self):
        with self.assertRaises(e.EconomyError):
            self.configure(facility="npc-factory")
        with self.assertRaises(e.EconomyError):
            self.configure(daily_budget_minor=5000001)
        with self.assertRaises(e.EconomyError):
            self.configure(enabled=1)
        with self.assertRaises(e.EconomyError):
            self.configure(facility="player-shop",buy_inputs=True)
        self.assertEqual(self.w["automation_rules"],{})
    def test_disable_stops_actions(self):
        self.configure(enabled=False)
        e.advance(self.w,24)
        self.assertFalse(any(ev["action"]=="buy" for ev in self.w["automation_events"]))
    def test_shop_restock_and_pricing(self):
        self.configure(facility="player-shop",buy_inputs=False,production=False,
                       restock=True,pricing=True,stock_target=40)
        self.w["facilities"]["npc-shop"]["stock"]["bread"] = 30
        self.w["facilities"]["npc-shop"]["prices"]["bread"] = 12000
        before=self.w["facilities"]["player-shop"]["stock"]["bread"]
        e.advance(self.w,11)
        self.w["audit"]["bread"]["sourced"] += 30
        self.w["facilities"]["npc-shop"]["stock"]["bread"] = 30
        e.advance(self.w,1)
        self.assertGreaterEqual(self.w["facilities"]["player-shop"]["stock"]["bread"],0)
        self.assertTrue(any(ev["action"] in ("restock","price") for ev in self.w["automation_events"]))
        self.assertTrue(e.audit_world(self.w))
    def test_private_snapshot_and_journal_bound(self):
        self.configure()
        self.assertEqual(len(e.snapshot(self.w,"player")["automation_rules"]),1)
        self.assertEqual(e.snapshot(self.w,"rival")["automation_rules"],{})
        e.advance(self.w,360)
        self.assertLessEqual(len(self.w["automation_events"]),100)
        self.assertTrue(e.audit_world(self.w))
    def test_determinism(self):
        self.configure()
        other=copy.deepcopy(self.w)
        e.advance(self.w,360)
        e.advance(other,360)
        self.assertEqual(self.w,other)
        self.assertTrue(e.audit_world(self.w))
    def test_idempotent_rule_configuration(self):
        cmd={"type":"automation.configure","facility_id":"player-factory",
             "command_id":"automation083-fixed","expected_revision":self.w["revision"],
             "enabled":False,"buy_inputs":False,"restock":False,"production":False,
             "pricing":False,"daily_budget_minor":0,"stock_target":0,
             "max_purchase_units":1,"production_target":0,"undercut_minor":0}
        first=e.apply_command(self.w,"player",cmd)
        second=e.apply_command(self.w,"player",cmd)
        self.assertEqual(first,second)
        self.assertEqual(len(self.w["automation_events"]),1)
if __name__=="__main__":
    unittest.main()