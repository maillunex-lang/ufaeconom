"""Real spatial retail allocation regression tests."""
import copy
import unittest
from server import economy as e

class SpatialRetailTests(unittest.TestCase):
    def test_proximity_and_competition_change_score(self):
        f={"id":"a","plot":{"x":0,"y":0}}
        near=e._district_retail_score(f,[f])
        f["plot"]={"x":40,"y":40}
        self.assertGreater(e._district_retail_score(f,[f]),near)
        f["plot"]={"x":0,"y":0}
        rival={"id":"b","plot":{"x":1,"y":1}}
        self.assertGreater(e._district_retail_score(f,[f,rival]),near)
    def test_location_changes_actual_sales_and_conserves_money(self):
        base=e.new_world()
        shops=[base["facilities"]["player-shop"],base["facilities"]["npc-shop"]]
        for fac in shops:
            fac["city"]="ufa"
            fac["prices"]["bread"]=e.BASE_PRICES["bread"]
            fac["customer_distance_km"]=3
            fac["reputation"]=70
        # Additional bread is sourced to preserve inventory audit.
        for fac in shops:
            diff=30-fac["stock"]["bread"]
            if diff>0:
                e._put(fac,"bread",diff,0)
                base["audit"]["bread"]["sourced"]+=diff
        a=copy.deepcopy(base);b=copy.deepcopy(base)
        a["facilities"]["player-shop"]["plot"]={"x":0,"y":0}
        a["facilities"]["npc-shop"]["plot"]={"x":48,"y":48}
        b["facilities"]["player-shop"]["plot"]={"x":48,"y":48}
        b["facilities"]["npc-shop"]["plot"]={"x":0,"y":0}
        for w in (a,b):
            initial=e.money_total(w)
            e._retail(w)
            self.assertEqual(e.money_total(w),initial)
        self.assertGreater(a["last_sales"]["player-shop:bread"]["units"],b["last_sales"].get("player-shop:bread",{}).get("units",0))

if __name__=="__main__":
    unittest.main()