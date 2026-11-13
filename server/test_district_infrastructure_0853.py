"""District infrastructure integration regression tests."""
import copy
import unittest
from server import economy as e

class DistrictInfrastructureTests(unittest.TestCase):
    def test_road_and_housing_counts_match_existing_map(self):
        w=e.new_world()
        data=e._district_infrastructure(w,"ufa",(0,0))
        self.assertGreater(data["roads"],0)
        self.assertGreaterEqual(data["housing_tiles"],0)
        self.assertTrue(0<=data["attractiveness"]<=100)
        self.assertEqual(data,e._district_infrastructure(w,"ufa",(0,0)))
    def test_services_and_jobs_increase_attractiveness(self):
        a=e.new_world();b=copy.deepcopy(a)
        shop=b["facilities"]["player-shop"]
        shop["workers"]=40
        district=(shop["plot"]["x"]//16,shop["plot"]["y"]//16)
        self.assertGreaterEqual(e._district_infrastructure(b,"ufa",district)["attractiveness"],
                                e._district_infrastructure(a,"ufa",district)["attractiveness"])
    def test_monthly_migration_uses_attractiveness(self):
        w=e.new_world()
        before=e._district_population("ufa",(0,0),w)
        infra=e._district_infrastructure(w,"ufa",(0,0))
        e._update_district_population(w)
        expected=max(-8,min(8,(infra["attractiveness"]-50)//8))
        self.assertEqual(e._district_population("ufa",(0,0),w),before+expected)
        self.assertTrue(e.audit_world(w))
    def test_snapshot_contains_infrastructure_without_mutation(self):
        w=e.new_world(); before=copy.deepcopy(w)
        districts=e.district_demand(w,"player")
        self.assertTrue(districts)
        self.assertTrue(all("infrastructure" in d for d in districts))
        self.assertEqual(w,before)

if __name__=="__main__":
    unittest.main()