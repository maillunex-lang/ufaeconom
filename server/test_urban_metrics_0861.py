import copy
import unittest
from server import economy as e

class UrbanMetricsTests(unittest.TestCase):
    def setUp(self):
        self.w=e.new_world()
    def test_transport_access_road_and_investment(self):
        w=self.w
        a=e._district_urban_metrics(w,"ufa",(0,0))
        w["district_investments"]={"ufa":{"0:0":4}}
        b=e._district_urban_metrics(w,"ufa",(0,0))
        self.assertGreaterEqual(b["transport_access"],a["transport_access"])
        self.assertTrue(0<=b["transport_access"]<=100)
    def test_congestion_reflects_population(self):
        w=self.w
        a=e._district_urban_metrics(w,"ufa",(0,0))
        w["district_population"]={"ufa":{"0:0":4500}}
        b=e._district_urban_metrics(w,"ufa",(0,0))
        self.assertGreaterEqual(b["traffic_congestion"],a["traffic_congestion"])
        self.assertTrue(0<=b["traffic_congestion"]<=100)
    def test_land_price_indicative_and_specialization(self):
        a=e._district_urban_metrics(self.w,"ufa",(0,0))
        self.assertGreater(a["indicative_land_value_minor"],0)
        self.assertIn(a["specialization"],("industrial","commercial","residential","mixed"))
        self.assertIsInstance(a["indicative_land_value_minor"],int)
    def test_snapshot_readonly_and_economy(self):
        w=self.w
        before=copy.deepcopy(w)
        rows=e.district_demand(w,"player")
        self.assertTrue(rows)
        self.assertTrue(all("urban_metrics" in row for row in rows))
        self.assertEqual(w,before)
        e.advance(w,e.TICKS_PER_MONTH)
        self.assertTrue(e.audit_world(w))

if __name__=="__main__":
    unittest.main()