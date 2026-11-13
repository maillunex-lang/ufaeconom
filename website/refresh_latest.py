#!/usr/bin/env python3
"""Publish only the newest valid Business Empire Online Android APK.

Scans the existing server's APK directory, validates package/version/signature,
and atomically updates a permanent symlink and JSON manifest. Never builds APKs,
never changes other games and never enables an in-app update mechanism.
"""
from __future__ import annotations

import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

WEBROOT = Path("/var/www/rikagro-game")
SOURCE = WEBROOT / "agrogame/download"
SITE = WEBROOT / "business-empire"
TARGET = SITE / "download/BusinessEmpireOnline-latest.apk"
MANIFEST = SITE / "release/latest.json"
LOCK = Path("/tmp/ufaeconom-apk-refresh.lock")
AAPT = "/opt/android-sdk/build-tools/35.0.0/aapt"
APKSIGNER = "/opt/android-sdk/build-tools/35.0.0/apksigner"
PACKAGE = "com.ufaeconom.business"
CERT_SHA256 = "c4d731bf72cad32c9f94e19dc61c5ca6cc6ebc6e29deb11490093203bdfc1720"
FILENAME_RE = re.compile(r"^BusinessEmpireOnline-(\d+)\.(\d+)(?:\.(\d+))?-(?:debug|release)\.apk$")
PKG_RE = re.compile(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", re.M)
CERT_RE = re.compile(r"Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]{64})")


def execute(*cmd: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
    if result.returncode:
        raise ValueError(f"Verification failed: {cmd[0]} exited {result.returncode}: {result.stderr[-200:]}")
    return result.stdout


def inspect(path: Path) -> dict | None:
    match = FILENAME_RE.fullmatch(path.name)
    if not match or not path.is_file() or path.is_symlink():
        return None
    if not (1_000_000 <= path.stat().st_size < 600_000_000):
        return None
    expected = (int(match[1]), int(match[2]), int(match[3] or 0))
    try:
        badging = execute(AAPT, "dump", "badging", str(path))
        found = PKG_RE.search(badging)
        if not found or found[1] != PACKAGE:
            return None
        code = int(found[2])
        version = found[3]
        groups = version.split(".")
        if len(groups) not in (2, 3) or any(not v.isdecimal() for v in groups):
            return None
        triple = tuple(int(v) for v in groups)
        if len(triple) == 2:
            triple += (0,)
        if triple != expected or code < 1:
            return None
        signer = execute(APKSIGNER, "verify", "--print-certs", str(path))
        cert = CERT_RE.search(signer)
        if not cert or cert[1].lower() != CERT_SHA256:
            return None
        size = path.stat().st_size
        digest = hashlib.file_digest(path.open("rb"), "sha256").hexdigest()
        return {
            "version": ".".join(str(v) for v in triple),
            "versionCode": code,
            "versionTuple": triple,
            "filename": path.name,
            "sizeBytes": size,
            "sha256": digest,
            "publishedAt": dt.datetime.fromtimestamp(path.stat().st_mtime, dt.timezone.utc).isoformat(),
            "packageId": PACKAGE,
            "downloadUrl": "/business-empire/download/BusinessEmpireOnline-latest.apk",
            "source": str(path),
        }
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def main() -> None:
    if not SOURCE.is_dir() or not SITE.is_dir():
        raise RuntimeError("The expected game download directory or landing directory is missing")
    with LOCK.open("w") as fp:
        fcntl.flock(fp, fcntl.LOCK_EX | fcntl.LOCK_NB)
        candidates = []
        for path in sorted(SOURCE.iterdir()):
            if FILENAME_RE.fullmatch(path.name):
                result = inspect(path)
                if result is not None:
                    candidates.append(result)
        if not candidates:
            raise RuntimeError("No valid, correctly signed BUSINESS EMPIRE ONLINE release")
        best = max(candidates, key=lambda c: (c["versionCode"], c["versionTuple"]))
        previous = {}
        if MANIFEST.is_file():
            try:
                previous = json.loads(MANIFEST.read_text("utf-8"))
            except (OSError, json.JSONDecodeError):
                previous = {}
        if int(previous.get("versionCode", 0)) > best["versionCode"]:
            raise RuntimeError("Refusing APK downgrade")
        if (
            previous.get("versionCode") == best["versionCode"]
            and previous.get("sha256") not in (None, best["sha256"])
        ):
            raise RuntimeError("Same versionCode but different APK checksum; manual release review required")
        if (
            previous.get("sha256") == best["sha256"]
            and TARGET.is_symlink()
            and TARGET.resolve() == Path(best["source"]).resolve()
        ):
            return
        TARGET.parent.mkdir(parents=True, exist_ok=True)
        MANIFEST.parent.mkdir(parents=True, exist_ok=True)
        temp_link = TARGET.with_name(".latest-apk.tmp." + str(os.getpid()))
        temp_manifest = MANIFEST.with_name(".latest-json.tmp." + str(os.getpid()))
        temp_link.unlink(missing_ok=True)
        temp_manifest.unlink(missing_ok=True)
        try:
            os.symlink(best["source"], temp_link)
            os.replace(temp_link, TARGET)
            data = {key: val for key, val in best.items() if key not in ("source", "versionTuple")}
            temp_manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            temp_manifest.chmod(0o644)
            os.replace(temp_manifest, MANIFEST)
        finally:
            temp_link.unlink(missing_ok=True)
            temp_manifest.unlink(missing_ok=True)
        print(f"Published latest APK: {best['version']} (code {best['versionCode']}), SHA256 {best['sha256']}")


if __name__ == "__main__":
    try:
        main()
    except BlockingIOError:
        sys.exit(0)  # Another verification is running.
    except Exception as exc:
        print(f"APK refresh ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
