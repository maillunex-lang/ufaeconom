import copy
import unittest
from server import economy as e

class RetailPerformanceTests(unittest.TestCase):
    def test_retail_is_deterministic_and_balanced(self):
        a=e.new_world()
        b=copy.deepcopy(a)
        e._retail(a)
        e._retail(b)
        self.assertEqual(a,b)
        self.assertTrue(e.audit_world(a))
    def test_empty_stock_no_sales(self):
        w=e.new_world()
        for f in w["facilities"].values():
            if f["kind"]=="shop":
                for good in ("bread","milk","flour"):
                    f["stock"][good]=0
        before=copy.deepcopy(w["wallets"])
        e._retail(w)
        self.assertEqual(w["wallets"],before)
        self.assertEqual(w["last_sales"],{})
    def test_no_shops_is_safe(self):
        w=e.new_world()
        w["facilities"]={k:f for k,f in w["facilities"].items() if f["kind"]!="shop"}
        e._retail(w)
        self.assertEqual(w["last_sales"],{})

if __name__=="__main__":
    unittest.main()