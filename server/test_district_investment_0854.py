"""Infrastructure investment is server-authoritative, bounded and idempotent."""
import copy
import unittest
from server import economy as e

class DistrictInvestmentTests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
        self.fac=self.w["facilities"]["player-shop"]
        self.city=self.fac["city"]
        self.district="%d:%d"%(self.fac["plot"]["x"]//16,self.fac["plot"]["y"]//16)
    def cmd(self,actor="player",ident="invest0001",**extra):
        return {"type":"district.invest","city":self.city,"district":self.district,
                "command_id":ident,"expected_revision":self.w["revision"],**extra}
    def test_investment_receipt_balance_and_attractiveness(self):
        before=e.money_total(self.w)
        cash=self.w["wallets"]["company:player"]
        score=e._district_infrastructure(self.w,self.city,tuple(map(int,self.district.split(":"))))["attractiveness"]
        command=self.cmd()
        result=e.apply_command(self.w,"player",command)
        self.assertEqual(result["cost_minor"],2_000_000)
        self.assertEqual(self.w["wallets"]["company:player"],cash-2_000_000)
        self.assertEqual(e.money_total(self.w),before)
        self.assertEqual(e.apply_command(self.w,"player",command),result)
        self.assertEqual(self.w["wallets"]["company:player"],cash-2_000_000)
        self.assertGreaterEqual(e._district_infrastructure(self.w,self.city,tuple(map(int,self.district.split(":"))))["attractiveness"],score)
        self.assertTrue(e.audit_world(self.w))
    def test_not_owned_and_invalid_district(self):
        before=copy.deepcopy(self.w)
        with self.assertRaises(e.EconomyError):
            e.apply_command(self.w,"rival",self.cmd())
        with self.assertRaises(e.EconomyError):
            e.apply_command(self.w,"player",self.cmd(district="999:999"))
        self.assertEqual(self.w,before)
    def test_level_cap_and_legacy_migration(self):
        self.w.pop("district_investments",None)
        e.migrate_industry(self.w)
        for i in range(5):
            result=e.apply_command(self.w,"player",self.cmd(ident=f"invest{i:04d}"))
            self.assertEqual(result["level"],i+1)
        with self.assertRaises(e.EconomyError):
            e.apply_command(self.w,"player",self.cmd(ident="invest9999"))
        self.assertEqual(self.w["district_investments"][self.city][self.district],5)
    def test_insufficient_funds(self):
        self.w["wallets"]["company:player"]=0
        with self.assertRaises(e.EconomyError):
            e.apply_command(self.w,"player",self.cmd())

if __name__=="__main__":
    unittest.main()