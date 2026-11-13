"""Monthly district migration: bounded, persisted, deterministic."""
import copy
import unittest
from server import economy as e

class DynamicPopulationTests(unittest.TestCase):
    def test_monthly_update_and_bounds(self):
        w=e.new_world()
        before=e._district_population("ufa",(0,0),w)
        e.advance(w,e.TICKS_PER_MONTH)
        after=e._district_population("ufa",(0,0),w)
        self.assertNotEqual(before,after)
        self.assertLessEqual(abs(after-before),8)
        self.assertTrue(e.audit_world(w))
    def test_determinism_and_migration(self):
        a=e.new_world()
        b=copy.deepcopy(a)
        for w in (a,b):
            w.pop("district_population",None)
            e.migrate_industry(w)
            e.advance(w,e.TICKS_PER_MONTH)
        self.assertEqual(a,b)
        self.assertTrue(a["district_population"])
    def test_jobs_and_services_affect_population(self):
        a=e.new_world();b=copy.deepcopy(a)
        shop=b["facilities"]["player-shop"]
        shop["workers"]=12
        e._update_district_population(a)
        e._update_district_population(b)
        district=(shop["plot"]["x"]//16,shop["plot"]["y"]//16)
        self.assertGreaterEqual(e._district_population("ufa",district,b),
                                e._district_population("ufa",district,a))
    def test_demand_weights_reflect_population(self):
        w=e.new_world()
        shops=[f for f in w["facilities"].values() if f["city"]=="ufa" and f["kind"]=="shop"]
        initial=e._district_sales_weights("ufa",shops,w)
        w["district_population"]={"ufa":{"0:0":4000}}
        changed=e._district_sales_weights("ufa",shops,w)
        self.assertEqual(changed[(0,0)],4000)
        self.assertNotEqual(initial,changed)
        self.assertEqual(sum(e._allocate_district_demand(11,changed).values()),11)

if __name__=="__main__":
    unittest.main()