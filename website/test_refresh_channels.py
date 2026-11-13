"""No-runtime-side-effects checks for landing release channel updater."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from website import refresh_channels as channels

class LandingChannelTests(unittest.TestCase):
    def setUp(self):
        self.stable={"version":"0.4.0","versionCode":4,"sha256":"a"*64,"sizeBytes":27575788,
                     "packageId":channels.PACKAGE,"downloadUrl":channels.STABLE_URL,
                     "publishedAt":"2026-11-13T08:33:15+00:00"}
        self.beta={"version":"0.7.0-beta","versionCode":7,"versionTuple":(0,7,0),
                   "sha256":"b"*64,"sizeBytes":27618811,"packageId":channels.PACKAGE,
                   "downloadUrl":"/business-empire/beta/BusinessEmpireOnline-0.7.0-beta.apk",
                   "publishedAt":"2026-11-13T10:35:00+00:00",
                   "notes":"Отдельная beta","channel":"beta","networkServerPublic":False}

    def test_stable_and_beta_independent(self):
        data=channels.reconcile(self.stable,[self.beta])
        self.assertEqual(data["stable"]["version"],"0.4.0")
        self.assertEqual(data["beta"]["version"],"0.7.0-beta")
        self.assertFalse(data["beta"]["networkServerPublic"])
        self.assertEqual(data["serverStatus"],"private_test_only")
        self.assertNotIn("versionTuple",data["beta"])

    def test_only_valid_higher_beta_selected(self):
        old={**self.beta,"version":"0.3.0-beta","versionCode":3,
             "versionTuple":(0,3,0)}
        higher={**self.beta,"version":"0.7.1-beta","versionCode":8,
                "versionTuple":(0,7,1)}
        self.assertEqual(channels.reconcile(self.stable,[old,self.beta,higher])["beta"]["version"],
                         "0.7.1-beta")
        self.assertIsNone(channels.reconcile(self.stable,[old])["beta"])

    def test_tampered_stable_refused(self):
        with self.assertRaises(ValueError):
            channels.reconcile({**self.stable,"packageId":"wrong"},[self.beta])
        with self.assertRaises(ValueError):
            channels.reconcile({**self.stable,"sha256":"bad"},[self.beta])
        with self.assertRaises(ValueError):
            channels.reconcile({**self.stable,"downloadUrl":"https://evil.test/app.apk"},[self.beta])

    def test_atomic_idempotent_rewrite(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/"release/channels.json"
            data=channels.reconcile(self.stable,[self.beta])
            self.assertTrue(channels.write_atomic(path,data))
            self.assertEqual(json.loads(path.read_text())["beta"]["versionCode"],7)
            self.assertFalse(channels.write_atomic(path,data))
            self.assertTrue(channels.write_atomic(path,{**data,"status":"changed"}))
            self.assertFalse(list(path.parent.glob(".channels.*")))

    def test_invalid_apk_filename_or_symlink_not_used(self):
        with tempfile.TemporaryDirectory() as d:
            folder=Path(d)
            (folder/"BusinessEmpireOnline-unverified.apk").write_bytes(b"data")
            self.assertIsNone(channels.inspect_apk(folder/"BusinessEmpireOnline-unverified.apk"))
            (folder/"BusinessEmpireOnline-0.9.0-beta.apk").symlink_to(folder/"BusinessEmpireOnline-unverified.apk")
            self.assertIsNone(channels.inspect_apk(folder/"BusinessEmpireOnline-0.9.0-beta.apk"))

    def test_manifest_reconciliation_from_verified_inputs(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d)
            beta=root/"beta"
            beta.mkdir()
            path=beta/"BusinessEmpireOnline-0.7.0-beta.apk"
            path.write_bytes(b"x"*1_000_000)
            stable=root/"latest.json"
            stable.write_text(json.dumps(self.stable),encoding="utf-8")
            out=root/"channels.json"
            with patch.object(channels,"inspect_apk",return_value=self.beta):
                with patch("sys.argv",["refresh_channels","--stable",str(stable),
                        "--beta-dir",str(beta),"--output",str(out)]):
                    channels.main()
            self.assertEqual(json.loads(out.read_text())["beta"]["version"],"0.7.0-beta")
            self.assertEqual(json.loads(out.read_text())["stable"]["version"],"0.4.0")

if __name__=="__main__":
    unittest.main(verbosity=2)
