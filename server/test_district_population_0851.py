"""District population and actual retail allocation tests."""
import copy
import unittest
from server import economy as e

class DistrictPopulationTests(unittest.TestCase):
    def test_population_weights_and_exact_demand(self):
        w=e.new_world()
        shops=[f for f in w["facilities"].values() if f["city"]=="ufa" and f["kind"]=="shop"]
        weights=e._district_sales_weights("ufa",shops)
        self.assertGreater(len(weights),1)
        self.assertGreater(weights[(0,0)],weights[(1,1)])
        for n in range(0,35):
            allocated=e._allocate_district_demand(n,weights)
            self.assertEqual(sum(allocated.values()),n)
            self.assertTrue(all(isinstance(v,int) and v>=0 for v in allocated.values()))
    def test_location_changes_actual_revenue_without_changing_city_demand(self):
        base=e.new_world()
        shops=[base["facilities"]["player-shop"],base["facilities"]["npc-shop"]]
        for fac in shops:
            fac["prices"]["bread"]=e.BASE_PRICES["bread"]
            fac["customer_distance_km"]=3
            fac["reputation"]=70
            needed=max(0,30-fac["stock"]["bread"])
            if needed:
                e._put(fac,"bread",needed,0)
                base["audit"]["bread"]["sourced"]+=needed
        a=copy.deepcopy(base);b=copy.deepcopy(base)
        a["facilities"]["player-shop"]["plot"]={"x":0,"y":0}
        a["facilities"]["npc-shop"]["plot"]={"x":32,"y":32}
        b["facilities"]["player-shop"]["plot"]={"x":32,"y":32}
        b["facilities"]["npc-shop"]["plot"]={"x":0,"y":0}
        for w in (a,b):
            money=e.money_total(w)
            e._retail(w)
            self.assertEqual(e.money_total(w),money)
            self.assertLessEqual(w["stats"]["units_sold"],sum(sum(g.values()) for g in e.DEMAND.values())*2)
        self.assertGreater(a["last_sales"]["player-shop:bread"]["units"],
                           b["last_sales"]["player-shop:bread"]["units"])
        self.assertEqual(a["stats"]["units_sold"],b["stats"]["units_sold"])
    def test_snapshot_reports_population_without_mutation(self):
        w=e.new_world()
        original=copy.deepcopy(w)
        districts=e.snapshot(w,"player")["district_demand"]
        self.assertTrue(districts)
        self.assertTrue(all(d["synthetic_population"]>0 for d in districts))
        self.assertEqual(w,original)

if __name__=="__main__":
    unittest.main()