#!/usr/bin/env python3
"""Reconcile published stable and beta APKs into atomic public release metadata.

Does not build APK, touch the stable APK symlink, modify other games or write
website copy. Independent of the existing stable updater. Stdlib only.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

PACKAGE = "com.ufaeconom.business"
CERT_SHA256 = "c4d731bf72cad32c9f94e19dc61c5ca6cc6ebc6e29deb11490093203bdfc1720"
APPROOT = Path("/var/www/rikagro-game/business-empire")
STABLE_FILE = APPROOT / "release/latest.json"
BETA_DIR = APPROOT / "beta"
OUTPUT = APPROOT / "release/channels.json"
AAPT = "/opt/android-sdk/build-tools/35.0.0/aapt"
APKSIGNER = "/opt/android-sdk/build-tools/35.0.0/apksigner"
BETA_RE = re.compile(r"^BusinessEmpireOnline-(\d+)\.(\d+)\.(\d+)-beta\.apk$")
PKG_RE = re.compile(r"^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'",re.M)
CERT_RE = re.compile(r"Signer #1 certificate SHA-256 digest: ([0-9a-f]{64})")
RELEASE_NOTES = {
    "0.7.0-beta": "Конкурентные компании, заводы, межгородские перевозки и отдельный тестовый MMO-клиент. Публичный сервер пока не запущен.",
}
STABLE_URL = "/business-empire/download/BusinessEmpireOnline-latest.apk"

def command(*parts: str) -> str:
    run = subprocess.run(parts,capture_output=True,text=True,timeout=25)
    if run.returncode:
        raise ValueError("APK validation failed: " + str(parts[0]))
    return run.stdout

def inspect_apk(path: Path) -> dict | None:
    match = BETA_RE.fullmatch(path.name)
    if not match or not path.is_file() or path.is_symlink():
        return None
    if not (1_000_000 <= path.stat().st_size <= 600_000_000):
        return None
    version_tuple = tuple(int(g) for g in match.groups())
    expected_version = ".".join(str(g) for g in version_tuple) + "-beta"
    try:
        badge=command(AAPT,"dump","badging",str(path))
        found=PKG_RE.search(badge)
        if not found or found[1]!=PACKAGE or found[3]!=expected_version:
            return None
        signer=command(APKSIGNER,"verify","--print-certs",str(path))
        cert=CERT_RE.search(signer)
        if cert is None or cert[1].lower()!=CERT_SHA256:
            return None
        with path.open("rb") as f:
            digest=hashlib.file_digest(f,"sha256").hexdigest()
        return {
            "version":expected_version,"versionCode":int(found[2]),
            "versionTuple":version_tuple,"sha256":digest,
            "sizeBytes":path.stat().st_size,"packageId":PACKAGE,
            "downloadUrl":"/business-empire/beta/"+path.name,
            "publishedAt":dt.datetime.fromtimestamp(path.stat().st_mtime,dt.timezone.utc).isoformat(),
            "notes":RELEASE_NOTES.get(expected_version,"Проверенная подписанная бета-сборка. Подробности в журнале изменений."),
            "channel":"beta","networkServerPublic":False,
        }
    except (ValueError,OSError,subprocess.TimeoutExpired):
        return None

def reconcile(stable: dict, betas: list[dict]) -> dict:
    if (stable.get("packageId") != PACKAGE or not isinstance(stable.get("versionCode"),int)
        or not re.fullmatch(r"\d+(?:\.\d+){1,2}",str(stable.get("version","")))
        or not re.fullmatch(r"[0-9a-f]{64}",str(stable.get("sha256","")))
        or stable.get("downloadUrl") != STABLE_URL):
        raise ValueError("Untrusted stable manifest: refusing to publish channels")
    stable_pub = {k: stable[k] for k in ("version","versionCode","sha256","sizeBytes","packageId","downloadUrl","publishedAt") if k in stable}
    stable_pub["channel"]="stable"
    stable_pub["notes"]="Основная проверенная одиночная Android-демоверсия."
    stable_pub["networkServerPublic"]=False
    clean=[]
    for item in betas:
        if item["packageId"]!=PACKAGE or item["versionCode"]<=stable["versionCode"]:
            continue
        clean.append(item)
    selected = max(clean,key=lambda x:(x["versionCode"],x["versionTuple"]),default=None)
    if selected:
        selected={k:v for k,v in selected.items() if k!="versionTuple"}
    return {"schema":1,"stable":stable_pub,"beta":selected,
            "serverStatus":"private_test_only",
            "serverNote":"Экономический MMO-сервер тестируется изолированно; публичного игрового подключения пока нет.",
            "releasePolicy":"Подписанные APK публикуются отдельно. Непроверенные ветки не считаются релизами."}

def write_atomic(path:Path,data:dict) -> bool:
    payload=(json.dumps(data,ensure_ascii=False,indent=2,sort_keys=True)+"\n").encode()
    if path.exists() and path.read_bytes()==payload:
        return False
    path.parent.mkdir(parents=True,exist_ok=True)
    fd,source=tempfile.mkstemp(prefix=".channels.",dir=path.parent)
    try:
        with os.fdopen(fd,"wb") as out:
            out.write(payload)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(source,0o644)
        os.replace(source,path)
        return True
    finally:
        if os.path.exists(source):os.unlink(source)

def main() -> None:
    ap=argparse.ArgumentParser()
    ap.add_argument("--stable",type=Path,default=STABLE_FILE)
    ap.add_argument("--beta-dir",type=Path,default=BETA_DIR)
    ap.add_argument("--output",type=Path,default=OUTPUT)
    args=ap.parse_args()
    stable=json.loads(args.stable.read_text(encoding="utf-8"))
    matches=[]
    if args.beta_dir.exists():
        for path in args.beta_dir.iterdir():
            valid=inspect_apk(path)
            if valid:
                matches.append(valid)
    status=reconcile(stable,matches)
    if write_atomic(args.output,status):
        print("CHANGED release channels stable=%s beta=%s" %
              (status["stable"]["version"],status["beta"]["version"] if status["beta"] else "none"))
    else:
        print("UNCHANGED release channels")

if __name__=="__main__":
    main()
