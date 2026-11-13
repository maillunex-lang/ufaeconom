"""Regression: optimized district snapshot preserves output and world."""
import copy
import unittest
from server import economy as e

class UrbanPerformanceTests(unittest.TestCase):
    def test_snapshot_stable_readonly(self):
        w=e.new_world()
        before=copy.deepcopy(w)
        a=e.district_demand(w,"player")
        b=e.district_demand(w,"player")
        self.assertEqual(a,b)
        self.assertEqual(w,before)
    def test_indicators_are_internally_consistent(self):
        w=e.new_world()
        for row in e.district_demand(w,"player"):
            coords=tuple(map(int,row["district"].split(":")))
            infra=e._district_infrastructure(w,row["city"],coords)
            self.assertEqual(row["infrastructure"],infra)
            self.assertEqual(row["urban_metrics"],e._district_urban_metrics(w,row["city"],coords,infra))
            self.assertEqual(row["residential_tier"],min(5,row["synthetic_population"]//750))
    def test_demand_allocation_and_audit(self):
        w=e.new_world()
        for city in e.CITIES:
            shops=[f for f in w["facilities"].values() if f["city"]==city and f["kind"]=="shop"]
            allocation=e._allocate_district_demand(e.DEMAND[city]["bread"],e._district_sales_weights(city,shops,w))
            self.assertEqual(sum(allocation.values()),e.DEMAND[city]["bread"])
        self.assertTrue(e.audit_world(w))
if __name__=="__main__":
    unittest.main()