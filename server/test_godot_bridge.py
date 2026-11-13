"""Contract integration: Godot 4 client against an isolated real HTTP server.

Requires GODOT_BIN in CI (otherwise skipped). Does not open any public port.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

from server.service import WorldHTTPServer, WorldStore


class GodotBridgeTests(unittest.TestCase):
    def test_godot_login_snapshot_and_command(self) -> None:
        godot = os.environ.get("GODOT_BIN")
        if not godot or not Path(godot).is_file():
            self.skipTest("Set GODOT_BIN for live Godot 4 bridge test")
        with tempfile.TemporaryDirectory(prefix="be-bridge-") as folder:
            store = WorldStore(Path(folder) / "world.db", epoch_unix=int(time.time()))
            server = None
            thread = None
            try:
                # Fixture credentials are local to this throwaway database.
                store.create_user("bridge_player", "bridge-temporary-01234", "player")
                server = WorldHTTPServer(("127.0.0.1", 0), store)
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                env = os.environ.copy()
                env.update({
                    "BE_TEST_URL": "http://127.0.0.1:" + str(server.server_address[1]),
                    "BE_TEST_USER": "bridge_player",
                    "BE_TEST_PASSWORD": "bridge-temporary-01234",
                })
                root = Path(__file__).resolve().parents[1]
                cmd = [godot, "--headless", "--path", str(root),
                       "--script", "res://tests/mmo_live_07.gd"]
                run = subprocess.run(cmd, cwd=root, env=env,
                                     capture_output=True, text=True, timeout=20)
                output = run.stdout + "\n" + run.stderr
                self.assertEqual(run.returncode, 0, output[-3000:])
                self.assertIn("MMO_LIVE_07_TESTS_PASSED", output, output[-3000:])
                self.assertEqual(store.world["facilities"]["player-shop"]["prices"]["bread"],
                                 15400)
            finally:
                if server is not None:
                    server.shutdown()
                    server.server_close()
                if thread is not None:
                    thread.join(timeout=3)
                store.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
