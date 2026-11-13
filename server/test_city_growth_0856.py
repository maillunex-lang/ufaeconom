import copy
import unittest
from server import economy as e

class CityGrowthFiveTests(unittest.TestCase):
    def test_residential_tier_and_trend(self):
        w=e.new_world()
        rows=e.district_demand(w,"player")
        self.assertTrue(rows)
        for row in rows:
            self.assertEqual(row["residential_tier"],min(5,row["synthetic_population"]//750))
            self.assertEqual(row["population_trend"],max(-8,min(8,(row["infrastructure"]["attractiveness"]-50)//8)))
    def test_growth_updates_visual_tier_and_trend(self):
        w=e.new_world()
        original=copy.deepcopy(w)
        e.district_demand(w,"player")
        self.assertEqual(w,original)
        w["district_population"]={"ufa":{"0:0":4500}}
        rows=e.district_demand(w,"player")
        central=next(row for row in rows if row["city"]=="ufa" and row["district"]=="0:0")
        self.assertEqual(central["residential_tier"],5)
        self.assertTrue(-8<=central["population_trend"]<=8)
    def test_legacy_save_and_economy_audit(self):
        w=e.new_world()
        w.pop("district_population",None)
        e.migrate_industry(w)
        e.advance(w,e.TICKS_PER_MONTH)
        self.assertTrue(e.audit_world(w))
        self.assertTrue(e.district_demand(w,"player"))
if __name__=="__main__":
    unittest.main()