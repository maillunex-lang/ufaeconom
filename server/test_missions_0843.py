from __future__ import annotations
import unittest
from server import economy, land

class ServerMissionTests(unittest.TestCase):
    def setUp(self):
        self.world = economy.new_world()
        self.actor = "player"
    def command(self, command_type, ident, **fields):
        return economy.apply_command(self.world, self.actor, {
            "type": command_type, "command_id": ident,
            "expected_revision": self.world["revision"], **fields})
    def test_claim_requires_actual_land_and_is_idempotent(self):
        self.assertTrue(economy.snapshot(self.world, self.actor)["missions"][0]["completed"])
        layout = self.world["land"]["ufa"]
        pos = land.free_plot("ufa", layout["chunks"], layout["plots"])
        self.assertIsNotNone(pos)
        x,y = pos
        self.command("land.buy", "m-buy-001", city="ufa", x=x,y=y)
        before = self.world["wallets"]["company:player"]
        reward = self.command("mission.claim", "m-claim-b", mission="first_land")
        self.assertEqual(reward["reward_minor"], 100000)
        self.assertEqual(self.world["wallets"]["company:player"], before+100000)
        self.assertEqual(economy.snapshot(self.world, self.actor)["missions"][0]["claimed"], True)
        with self.assertRaises(economy.EconomyError):
            self.command("mission.claim", "m-claim-c", mission="first_land")
        self.assertEqual(economy.apply_command(self.world, self.actor, {
            "type":"mission.claim", "command_id":"m-claim-b",
            "expected_revision":reward["revision"]-1, "mission":"first_land"}),reward)
        self.assertTrue(economy.audit_world(self.world))
    def test_build_mission_and_actor_isolation(self):
        layout = self.world["land"]["ufa"]
        x,y = land.free_plot("ufa", layout["chunks"], layout["plots"])
        self.command("land.buy","m-buy-002",city="ufa",x=x,y=y)
        self.assertTrue(economy.snapshot(self.world, self.actor)["missions"][1]["completed"])
        self.command("facility.build","m-build-002",city="ufa",kind="shop",x=x,y=y)
        reward = self.command("mission.claim","m-claim-e",mission="first_build")
        self.assertEqual(reward["reward_minor"],250000)
        self.assertFalse(economy.snapshot(self.world,"rival")["missions"][1]["claimed"])
        self.assertTrue(economy.audit_world(self.world))
    def test_unknown_and_delivery_not_claimable(self):
        with self.assertRaises(economy.EconomyError):
            self.command("mission.claim","m-claim-f",mission="first_delivery")
        with self.assertRaises(economy.EconomyError):
            self.command("mission.claim","m-claim-g",mission="fake")
        self.assertTrue(economy.audit_world(self.world))

if __name__ == "__main__":
    unittest.main()