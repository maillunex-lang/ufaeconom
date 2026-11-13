"""Stage 0.7 integration tests: sessions, two clients, persistence and recovery."""
from __future__ import annotations

import concurrent.futures
import json
import sqlite3
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from server import economy
from server.service import WorldHTTPServer, WorldStore


class StoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.db_path = Path(self.tmp.name) / "world.db"
        self.store = WorldStore(self.db_path, epoch_unix=1_800_000_000)

    def tearDown(self) -> None:
        self.store.close()
        self.tmp.cleanup()

    def test_replay_atomicity_and_restart(self) -> None:
        self.store.create_user("player_one", "123456789012safe", "player")
        token, actor = self.store.login("player_one", "123456789012safe")
        self.assertEqual(actor, self.store.authenticate(token))
        rev = self.store.snapshot(actor)["revision"]
        command = {
            "command_id": "stage07-buy-001",
            "expected_revision": rev, "type": "facility.buy",
            "facility_id": "player-shop", "good": "milk", "quantity": 5,
        }
        first = self.store.issue(actor, command)
        self.assertTrue(first["ok"])
        self.assertEqual(self.store.issue(actor, command), first)
        self.assertEqual(len(self.store.world["receipts"]), 1)
        after_purchase = self.store.snapshot(actor)["cash_minor"]
        with self.assertRaises(economy.EconomyError):
            self.store.issue(actor, {**command, "quantity": 10})
        self.assertEqual(after_purchase, self.store.snapshot(actor)["cash_minor"])
        with self.assertRaises(economy.EconomyError):
            self.store.issue(actor, {
                "command_id": "stage07-cheat", "expected_revision": first["revision"],
                "type": "facility.build", "city": "ufa", "kind": "shop",
                "now_unix": 2_200_000_000,
            })
        report = self.store.advance_if_due(1_800_000_000 + 720 * economy.TICK_SECONDS)
        self.assertEqual(report["processed"], 360)
        self.assertEqual(report["pending"], 360)
        self.assertEqual(self.store.advance_if_due(
            1_800_000_000 + 720 * economy.TICK_SECONDS)["pending"], 0)
        self.assertTrue(economy.audit_world(self.store.world))
        self.assertGreater(len(self.store.ledger("player")), 0)
        backup = Path(self.tmp.name) / "backup.db"
        self.store.backup(backup)
        self.assertEqual(sqlite3.connect(backup).execute("PRAGMA integrity_check").fetchone()[0], "ok")
        tick = self.store.world["tick"]
        balance = self.store.world["wallets"]["company:player"]
        self.store.close()
        self.store = WorldStore(self.db_path)
        self.assertEqual(self.store.world["tick"], tick)
        self.assertEqual(self.store.world["wallets"]["company:player"], balance)
        self.assertEqual(self.store.issue(actor, command), first)
        self.assertTrue(economy.audit_world(self.store.world))
        self.store.logout(token)
        with self.assertRaises(Exception):
            self.store.authenticate(token)

    def test_invalid_credentials(self) -> None:
        self.store.create_user("player_one", "123456789012safe", "player")
        with self.assertRaises(Exception):
            self.store.login("player_one", "incorrect-passcode")
        with self.assertRaises(Exception):
            self.store.login("missing", "incorrect-passcode")
        with self.assertRaises(Exception):
            self.store.create_user("npc_agent", "123456789012safe", "npc")
        with self.assertRaises(Exception):
            self.store.create_user("player_two", "short", "rival")


class HTTPTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.store = WorldStore(Path(self.tmp.name) / "world.db",
                                epoch_unix=1_800_000_000)
        self.store.create_user("player_one", "correct-horse-12345", "player")
        self.store.create_user("player_two", "super-secure-56789", "rival")
        self.httpd = WorldHTTPServer(("127.0.0.1", 0), self.store)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.url = "http://127.0.0.1:" + str(self.httpd.server_address[1])

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=3)
        self.store.close()
        self.tmp.cleanup()

    def call(self, path: str, body: dict | None = None, token: str | None = None):
        headers = {"Content-Type": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        raw = json.dumps(body).encode("utf-8") if body is not None else None
        req = Request(self.url + path, data=raw, headers=headers,
                      method="POST" if body is not None else "GET")
        try:
            with urlopen(req, timeout=5) as response:
                return response.status, json.loads(response.read())
        except HTTPError as error:
            return error.code, json.loads(error.read())

    def test_two_clients_auth_ownership_reconnect_commands(self) -> None:
        self.assertEqual(self.call("/v1/health")[0], 200)
        self.assertEqual(self.call("/v1/snapshot")[0], 401)
        st_a, login_a = self.call("/v1/login", {"username": "player_one",
                                                 "password": "correct-horse-12345"})
        st_b, login_b = self.call("/v1/login", {"username": "player_two",
                                                 "password": "super-secure-56789"})
        self.assertEqual((st_a, st_b), (200, 200))
        a, b = login_a["token"], login_b["token"]
        first_status, first = self.call("/v1/snapshot", token=a)
        self.assertEqual(first_status, 200)
        self.assertEqual(first["company"], "player")
        self.assertEqual(self.call("/v1/snapshot", token=b)[1]["company"], "rival")
        unauthorized = {
            "command_id": "client-0001", "expected_revision": first["revision"],
            "type": "facility.set_price", "facility_id": "rival-shop",
            "good": "bread", "price_minor": 12000,
        }
        self.assertEqual(self.call("/v1/command", unauthorized, a)[0], 400)
        rival_command = {**unauthorized, "command_id": "client-0002",
                         "price_minor": 14000}
        status, result = self.call("/v1/command", rival_command, b)
        self.assertEqual(status, 200)
        self.assertEqual(result["price_minor"], 14000)
        self.assertEqual(self.call("/v1/command", rival_command, b)[1], result)
        self.assertEqual(self.call("/v1/command", {**rival_command,
                          "price_minor": 15000}, b)[0], 400)
        self.assertEqual(self.call("/v1/command", {
            "command_id": "client-0003", "expected_revision": 0,
            "type": "facility.build", "city": "ufa", "kind": "warehouse",
        }, a)[0], 409)
        snapshot = self.call("/v1/snapshot", token=a)[1]
        status, built = self.call("/v1/command", {
            "command_id": "client-0004", "expected_revision": snapshot["revision"],
            "type": "facility.build", "city": "beloretsk", "kind": "warehouse",
        }, a)
        self.assertEqual(status, 200)
        self.assertIn(built["facility_id"], self.call("/v1/snapshot", token=a)[1]["facilities"])
        self.assertEqual(self.call("/v1/clock", token=a)[0], 200)
        self.assertEqual(self.call("/v1/ledger", token=a)[0], 200)
        self.assertEqual(self.call("/v1/snapshot", token=b)[1]["company"], "rival")
        # A fresh login acts as reconnection to the same persistent company.
        self.assertEqual(self.call("/v1/login", {"username": "player_one",
            "password": "correct-horse-12345"})[0], 200)
        self.assertEqual(self.store.authenticate(a), "player")
        self.assertEqual(self.call("/v1/logout", {}, a)[0], 200)
        self.assertEqual(self.call("/v1/snapshot", token=a)[0], 401)

    def test_parallel_readers_and_rejected_trust(self) -> None:
        token = self.call("/v1/login", {"username": "player_one",
                                       "password": "correct-horse-12345"})[1]["token"]
        with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
            results = list(pool.map(lambda _: self.call("/v1/snapshot", token=token),
                                    range(40)))
        self.assertTrue(all(code == 200 for code, _ in results))
        snapshot = self.call("/v1/snapshot", token=token)[1]
        self.assertEqual(self.call("/v1/command", {
            "command_id": "cheat-0001", "expected_revision": snapshot["revision"],
            "type": "facility.build", "kind": "shop", "city": "ufa",
            "actor": "npc", "wallets": {"company:player": 9999999999},
        }, token)[0], 400)
        self.assertTrue(economy.audit_world(self.store.world))


if __name__ == "__main__":
    unittest.main(verbosity=2)
