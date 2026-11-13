"""Isolated Godot ↔ HTTP spatial construction test. No persistent services."""
import os
from pathlib import Path
import subprocess
import tempfile
import threading
from server.service import WorldStore, WorldHTTPServer


def main():
    with tempfile.TemporaryDirectory(prefix="be-spatial-bridge-") as temporary:
        store=WorldStore(Path(temporary)/"world.sqlite", epoch_unix=1800000000)
        store.create_user("spatial_fixture", "spatial-test-only-password", "player")
        httpd=WorldHTTPServer(("127.0.0.1",0),store)
        thread=threading.Thread(target=httpd.serve_forever,daemon=True)
        thread.start()
        try:
            env=os.environ.copy()
            env.update(BE_TEST_URL="http://127.0.0.1:"+str(httpd.server_address[1]),
                       BE_TEST_USER="spatial_fixture",BE_TEST_PASSWORD="spatial-test-only-password",
                       XDG_DATA_HOME=temporary,GODOT_SILENCE_ROOT_WARNING="1")
            run=subprocess.run([env.get("GODOT_BINARY","godot"),"--headless","--path",".",
                                "--script","res://tests/mmo_land_live.gd"],
                               env=env,text=True,capture_output=True,timeout=30)
            print(run.stdout,run.stderr)
            if run.returncode or "MMO_LAND_LIVE_TESTS_PASSED" not in run.stdout or "SCRIPT ERROR" in run.stderr:
                raise SystemExit(1)
        finally:
            httpd.shutdown()
            httpd.server_close()
            thread.join(timeout=3)
            store.close()


if __name__=="__main__":main()
