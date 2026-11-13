"""Loopback-only authoritative MMO economy service (stage 0.7 beta).

Python standard library, SQLite WAL, atomic world snapshots and append-only ledger.
No public listener, automatic account registration or production deployment.
"""
from __future__ import annotations

import argparse
import fcntl
import getpass
import hashlib
import hmac
import json
import os
import re
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from . import economy

MAX_JSON_BYTES = 16384
TOKEN_LIFETIME = 7 * 86400
MAX_TICKS_PER_COMMIT = 360
_USER_RE = re.compile(r"^[A-Za-z0-9_]{3,32}$")


class AuthenticationError(Exception):
    pass


class WorldStore:
    """Serializes all changes under one lock; persistence and ledger commit together."""

    def __init__(self, db_path: str | Path, epoch_unix: int | None = None):
        self.lock = threading.RLock()
        self.path = str(db_path)
        # Single world writer per database, including the outbox and ledger.
        # Second server processes must fail fast instead of duplicating ticks.
        self._writer_lock = open(self.path + ".writer.lock", "a+b")
        try:
            fcntl.flock(self._writer_lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            self._writer_lock.close()
            raise RuntimeError("world database already has an authoritative worker") from exc
        self.db = sqlite3.connect(self.path, timeout=20, check_same_thread=False,
                                  isolation_level=None)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA busy_timeout=20000")
        db_version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if db_version not in (0, 1):
            raise RuntimeError("unsupported world database schema version")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS world_state (
                id INTEGER PRIMARY KEY CHECK(id = 1),
                revision INTEGER NOT NULL,
                payload TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS finance_ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                tick INTEGER NOT NULL,
                debit TEXT NOT NULL,
                credit TEXT NOT NULL,
                amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
                kind TEXT NOT NULL,
                reference TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS accounts (
                username TEXT PRIMARY KEY,
                actor TEXT NOT NULL UNIQUE,
                salt BLOB NOT NULL,
                password_hash BLOB NOT NULL,
                created_unix INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_digest TEXT PRIMARY KEY,
                username TEXT NOT NULL REFERENCES accounts(username),
                expires_unix INTEGER NOT NULL
            );
        """)
        if db_version == 0:
            self.db.execute("PRAGMA user_version=1")
        row = self.db.execute("SELECT payload FROM world_state WHERE id=1").fetchone()
        if row:
            self.world = json.loads(row[0])
            economy.migrate_industry(self.world)
            economy.land.ensure_world(self.world)
            if not economy.audit_world(self.world):
                raise RuntimeError("saved economy invariant failure; refuse to serve")
        else:
            epoch = int(time.time()) if epoch_unix is None else epoch_unix
            self.world = economy.new_world(epoch)
            self._save_world(self.world)

    @staticmethod
    def _hash_password(password: str, salt: bytes) -> bytes:
        return hashlib.scrypt(password.encode("utf-8"), salt=salt, n=16384,
                              r=8, p=1, dklen=32)

    def create_user(self, username: str, password: str, actor: str, city: str = "ufa") -> None:
        # Privileged local CLI only. No public registration endpoint.
        if not _USER_RE.fullmatch(username) or len(password) < 12 or len(password) > 256:
            raise ValueError("username or password fails policy")
        if (not isinstance(actor, str) or
                re.fullmatch(r"[a-z][a-z0-9_-]{2,24}", actor) is None or
                actor == "npc"):
            raise ValueError("invalid player company ID")
        salt = secrets.token_bytes(16)
        digest = self._hash_password(password, salt)
        with self.lock:
            account_row = (username, actor, salt, digest, int(time.time()))
            if "company:" + actor in self.world["wallets"]:
                self.db.execute("INSERT INTO accounts VALUES(?,?,?,?,?)", account_row)
                return
            candidate = economy.copy_world(self.world)
            economy.register_company(candidate, actor, city)
            self._save_world(candidate, lambda db: db.execute(
                "INSERT INTO accounts VALUES(?,?,?,?,?)", account_row))
            self.world = candidate

    def login(self, username: str, password: str) -> tuple[str, str]:
        if not isinstance(username, str) or not isinstance(password, str):
            raise AuthenticationError("invalid credentials")
        if len(username) > 32 or len(password) > 256:
            raise AuthenticationError("invalid credentials")
        with self.lock:
            row = self.db.execute(
                "SELECT actor,salt,password_hash FROM accounts WHERE username=?",
                (username,),
            ).fetchone()
            if row is None:
                raise AuthenticationError("invalid credentials")
            actor, salt, saved_hash = row
            calculated = self._hash_password(password, salt)
            if not hmac.compare_digest(calculated, saved_hash):
                raise AuthenticationError("invalid credentials")
            token = secrets.token_urlsafe(32)
            token_hash = hashlib.sha256(token.encode("ascii")).hexdigest()
            self.db.execute("INSERT INTO sessions VALUES (?,?,?)",
                            (token_hash, username, int(time.time()) + TOKEN_LIFETIME))
            return token, actor

    def authenticate(self, bearer: str) -> str:
        if not isinstance(bearer, str) or len(bearer) > 200 or not bearer:
            raise AuthenticationError("authentication required")
        token_hash = hashlib.sha256(bearer.encode("utf-8")).hexdigest()
        with self.lock:
            row = self.db.execute(
                "SELECT a.actor, s.expires_unix FROM sessions s "
                "JOIN accounts a ON a.username=s.username WHERE s.token_digest=?",
                (token_hash,),
            ).fetchone()
            if row is None or row[1] <= int(time.time()):
                raise AuthenticationError("session expired or invalid")
            return row[0]

    def logout(self, bearer: str) -> None:
        digest = hashlib.sha256(bearer.encode("utf-8")).hexdigest()
        with self.lock:
            self.db.execute("DELETE FROM sessions WHERE token_digest=?", (digest,))

    def _save_world(self, candidate: dict, extra_write=None) -> None:
        if not economy.audit_world(candidate):
            raise RuntimeError("economy invariant failed; refusing commit")
        payload = economy.copy_world(candidate)
        receipts = list(payload.get("pending_ledger", []))
        payload["pending_ledger"] = []
        serialized = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                                separators=(",", ":"))
        self.db.execute("BEGIN IMMEDIATE")
        try:
            self.db.execute(
                "INSERT INTO world_state(id,revision,payload) VALUES(1,?,?) "
                "ON CONFLICT(id) DO UPDATE SET "
                "revision=excluded.revision,payload=excluded.payload",
                (payload["revision"], serialized),
            )
            if receipts:
                self.db.executemany(
                    "INSERT INTO finance_ledger(tick,debit,credit,amount_minor,"
                    "kind,reference) VALUES(?,?,?,?,?,?)",
                    [(e["tick"], e["debit"], e["credit"], e["amount"],
                      e["kind"], e["ref"]) for e in receipts],
                )
            if extra_write is not None:
                extra_write(self.db)
            self.db.execute("COMMIT")
        except Exception:
            self.db.execute("ROLLBACK")
            raise
        candidate["pending_ledger"].clear()

    def advance_if_due(self, server_now_unix: int | None = None) -> dict:
        # Only the host worker calls this; never take server_now_unix from HTTP.
        now = int(time.time()) if server_now_unix is None else server_now_unix
        with self.lock:
            overdue = economy.due_ticks(self.world, now)
            amount = min(overdue, MAX_TICKS_PER_COMMIT)
            if amount:
                candidate = economy.copy_world(self.world)
                economy.advance(candidate, amount)
                self._save_world(candidate)
                self.world = candidate
            return {"processed": amount, "pending": overdue - amount,
                    "tick": self.world["tick"],
                    "revision": self.world["revision"]}

    def issue(self, actor: str, command: dict) -> dict:
        if not isinstance(command, dict):
            raise economy.EconomyError("invalid command")
        # Explicit denylist: client cannot submit authoritative state or clock.
        if any(k in command for k in ("actor", "wallets", "stock", "tick",
                                      "epoch_unix", "now_unix", "server_time")):
            raise economy.EconomyError("authoritative field prohibited")
        with self.lock:
            candidate = economy.copy_world(self.world)
            response = economy.apply_command(candidate, actor, command)
            if candidate != self.world:
                self._save_world(candidate)
                self.world = candidate
            return response

    def snapshot(self, actor: str) -> dict:
        with self.lock:
            return economy.snapshot(self.world, actor)

    def ledger(self, actor: str, after_id: int = 0, limit: int = 50) -> list[dict]:
        if (not isinstance(actor, str) or actor == "npc" or
                "company:" + actor not in self.world["wallets"] or
                not 0 <= after_id <= 10**12):
            raise economy.EconomyError("invalid history cursor")
        ident = "company:" + actor
        with self.lock:
            rows = self.db.execute(
                "SELECT id,tick,debit,credit,amount_minor,kind,reference "
                "FROM finance_ledger WHERE id>? AND (debit=? OR credit=?) "
                "ORDER BY id LIMIT ?",
                (after_id, ident, ident, max(1, min(limit, 100))),
            ).fetchall()
            return [dict(zip(("id", "tick", "debit", "credit", "amount_minor",
                              "kind", "reference"), r)) for r in rows]

    def backup(self, destination: str | Path) -> None:
        path = Path(destination)
        if path.resolve() == Path(self.path).resolve():
            raise ValueError("backup destination must differ from source")
        with self.lock:
            target = sqlite3.connect(str(path))
            try:
                self.db.backup(target)
            finally:
                target.close()

    def close(self) -> None:
        with self.lock:
            self.db.close()
            fcntl.flock(self._writer_lock.fileno(), fcntl.LOCK_UN)
            self._writer_lock.close()


class WorldHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], store: WorldStore):
        # Prevent accidentally exposing authentication over plain HTTP.
        if address[0] not in ("127.0.0.1", "localhost", "::1"):
            raise ValueError("HTTP beta may bind ONLY to loopback")
        super().__init__(address, WorldHandler)
        self.world_store = store
        self.rate_lock = threading.Lock()
        self.attempts: dict[str, list[float]] = {}

    def rate_ok(self, key: str, limit: int = 60) -> bool:
        now = time.monotonic()
        with self.rate_lock:
            recent = [ts for ts in self.attempts.get(key, []) if now - ts <= 60]
            if len(recent) >= limit:
                self.attempts[key] = recent
                return False
            recent.append(now)
            self.attempts[key] = recent
            return True


class WorldHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format_string: str, *args: object) -> None:
        # No auth tokens, usernames or submitted commands in access logs.
        return

    def _respond(self, code: int, payload: dict | list) -> None:
        raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    @property
    def store(self) -> WorldStore:
        return self.server.world_store  # type: ignore[attr-defined]

    def _body(self) -> dict:
        size = self.headers.get("Content-Length")
        if size is None or not size.isascii() or not size.isdecimal():
            raise ValueError("content-length required")
        count = int(size)
        if count < 1 or count > MAX_JSON_BYTES:
            raise ValueError("invalid JSON payload size")
        raw = self.rfile.read(count)
        doc = json.loads(raw)
        if not isinstance(doc, dict):
            raise ValueError("expected JSON object")
        return doc

    def _actor(self) -> tuple[str, str]:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            raise AuthenticationError("authentication required")
        token = header[7:]
        return self.store.authenticate(token), token

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(10)

    def _handle(self, method: str) -> None:
        path = urlsplit(self.path).path
        try:
            if method == "GET" and path == "/v1/health":
                self._respond(200, {"status": "ok", "protocol_version": 1})
                return
            if method == "POST" and path == "/v1/login":
                if not self.server.rate_ok("login:" + self.client_address[0], 10):
                    self._respond(429, {"error": "rate limit"})
                    return
                request = self._body()
                token, actor = self.store.login(request.get("username"),
                                                request.get("password"))
                self._respond(200, {"token": token, "actor": actor,
                                    "expires_in": TOKEN_LIFETIME})
                return
            actor, token = self._actor()
            if method == "GET" and path == "/v1/snapshot":
                self._respond(200, self.store.snapshot(actor))
            elif method == "GET" and path == "/v1/clock":
                current = self.store.snapshot(actor)
                self._respond(200, {"tick": current["tick"],
                                    "revision": current["revision"],
                                    "game_day": current["game_day"],
                                    "server_unix": int(time.time()),
                                    "tick_seconds": economy.TICK_SECONDS})
            elif method == "GET" and path == "/v1/ledger":
                query = parse_qs(urlsplit(self.path).query)
                after = int(query.get("after", ["0"])[0])
                self._respond(200, {"entries": self.store.ledger(actor, after)})
            elif method == "POST" and path == "/v1/logout":
                self.store.logout(token)
                self._respond(200, {"ok": True})
            elif method == "POST" and path == "/v1/command":
                token_digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
                if not self.server.rate_ok("cmd:" + token_digest, 120):
                    self._respond(429, {"error": "rate limit"})
                    return
                result = self.store.issue(actor, self._body())
                self._respond(200, result)
            else:
                self._respond(404, {"error": "not found"})
        except AuthenticationError:
            self._respond(401, {"error": "authentication required"})
        except economy.EconomyError as exc:
            status = 409 if str(exc) == "stale world revision" else 400
            self._respond(status, {"error": str(exc)})
        except (ValueError, TypeError, json.JSONDecodeError):
            self._respond(400, {"error": "invalid request"})
        except sqlite3.DatabaseError:
            self._respond(503, {"error": "storage unavailable"})
        except Exception:
            # Do not disclose a traceback or credentials to remote clients.
            import traceback
            traceback.print_exc()
            self._respond(500, {"error": "internal server error"})

    def do_GET(self) -> None:
        self._handle("GET")

    def do_POST(self) -> None:
        self._handle("POST")


def serve(store: WorldStore, host: str = "127.0.0.1", port: int = 4189) -> None:
    server = WorldHTTPServer((host, port), store)
    stop = threading.Event()

    def worker() -> None:
        while not stop.is_set():
            try:
                result = store.advance_if_due()
                if result["pending"] > 0:
                    # Catch up promptly but never skip committed ticks.
                    continue
            except Exception:
                # Do not let failed persistence silently advance the clock.
                import traceback
                traceback.print_exc()
            stop.wait(1.0)

    worker_thread = threading.Thread(target=worker, name="be-world-worker", daemon=True)
    worker_thread.start()
    try:
        server.serve_forever(poll_interval=0.5)
    finally:
        stop.set()
        server.server_close()
        worker_thread.join(timeout=5)


def main() -> None:
    parser = argparse.ArgumentParser(description="Loopback-only Business Empire MMO beta")
    commands = parser.add_subparsers(dest="action", required=True)
    for name in ("run", "create-user", "backup"):
        cmd = commands.add_parser(name)
        cmd.add_argument("--db", required=True)
        if name == "run":
            cmd.add_argument("--host", default="127.0.0.1")
            cmd.add_argument("--port", type=int, default=4189)
        elif name == "create-user":
            cmd.add_argument("--username", required=True)
            cmd.add_argument("--actor", required=True)
            cmd.add_argument("--city", default="ufa", choices=economy.CITIES)
        elif name == "backup":
            cmd.add_argument("--output", required=True)
    args = parser.parse_args()
    db_path = Path(args.db)
    if not db_path.parent.exists():
        parser.error("database parent directory must exist")
    if args.action == "backup":
        # SQLite online backup reads a consistent WAL snapshot, without
        # taking a second authoritative writer lease or stopping 24/7 ticks.
        if not db_path.exists() or db_path.resolve() == Path(args.output).resolve():
            parser.error("invalid backup source or destination")
        source = sqlite3.connect("file:" + str(db_path.resolve()) + "?mode=ro", uri=True)
        destination = sqlite3.connect(args.output)
        try:
            source.backup(destination)
        finally:
            destination.close()
            source.close()
        print("backup completed")
        return
    store = WorldStore(db_path)
    try:
        if args.action == "run":
            serve(store, args.host, args.port)
        elif args.action == "create-user":
            password = getpass.getpass("New account password (12+ chars): ")
            store.create_user(args.username, password, args.actor, args.city)
            print("account created")
    finally:
        store.close()


if __name__ == "__main__":
    main()