"""
SoulSync Persistent PostgreSQL Backend (Supabase / Neon / Render Postgres).
Provides transactional load_db(), save_db(), relational mirror tables, and health checks.
Fails closed in production if DATABASE_URL is missing or unreachable (never silently falls back to ephemeral JSON).
"""

import json
import os
import threading
from datetime import datetime, timezone

try:
    import psycopg2
    import psycopg2.extras
    HAS_PSYCOPG2 = True
except ImportError:
    HAS_PSYCOPG2 = False


class DatabaseUnavailableError(RuntimeError):
    """Raised when the production PostgreSQL database is unconfigured or unreachable."""


DB_LOCK = threading.RLock()


def get_database_url():
    return (os.environ.get("DATABASE_URL") or os.environ.get("SUPABASE_DB_URL") or "").strip()


def is_postgres_enabled():
    return bool(get_database_url())


def is_production_runtime():
    return bool(os.environ.get("RENDER") or os.environ.get("SOULSYNC_PROD"))


def _connect():
    if not HAS_PSYCOPG2:
        raise DatabaseUnavailableError("psycopg2-binary is not installed on the server.")
    url = get_database_url()
    if not url:
        raise DatabaseUnavailableError("DATABASE_URL is not configured.")
    if "sslmode=" not in url and "localhost" not in url and "127.0.0.1" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}sslmode=require"
    return psycopg2.connect(url, connect_timeout=10)


def init_postgres_schema():
    """Idempotently create SoulSync PostgreSQL tables, constraints, and indexes."""
    with _connect() as conn:
        with conn.cursor() as cur:
            cur.execute("""
                CREATE TABLE IF NOT EXISTS soulsync_collections (
                    collection_key TEXT PRIMARY KEY,
                    payload JSONB NOT NULL,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );

                CREATE TABLE IF NOT EXISTS soulsync_users (
                    id TEXT PRIMARY KEY,
                    email TEXT UNIQUE NOT NULL,
                    name TEXT NOT NULL,
                    couple_id TEXT,
                    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
                    is_active BOOLEAN NOT NULL DEFAULT TRUE,
                    password_hash TEXT,
                    invite_code TEXT,
                    social_provider TEXT,
                    social_account TEXT,
                    created_at TEXT,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );
                CREATE INDEX IF NOT EXISTS idx_soulsync_users_couple ON soulsync_users(couple_id);

                CREATE TABLE IF NOT EXISTS soulsync_couples (
                    id TEXT PRIMARY KEY,
                    code TEXT,
                    p1_id TEXT,
                    p2_id TEXT,
                    status TEXT,
                    created_at TEXT,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );
                CREATE INDEX IF NOT EXISTS idx_soulsync_couples_code ON soulsync_couples(code);

                CREATE TABLE IF NOT EXISTS soulsync_admins (
                    id TEXT PRIMARY KEY,
                    email TEXT UNIQUE NOT NULL,
                    role TEXT NOT NULL,
                    is_active BOOLEAN NOT NULL DEFAULT TRUE,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                );
            """)
        conn.commit()


def check_db_health():
    """Verify live PostgreSQL connectivity via SELECT 1."""
    if not is_postgres_enabled():
        if is_production_runtime():
            return False, "postgresql_unconfigured"
        return True, "local_json"
    try:
        with _connect() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        return True, "postgresql_connected"
    except Exception:
        return False, "postgresql_unavailable"


def load_pg_db(ensure_fn, fallback_seed_file=None):
    """Load all collections from PostgreSQL; auto-seeds once from fallback_seed_file if empty."""
    with DB_LOCK:
        try:
            init_postgres_schema()
            with _connect() as conn:
                with conn.cursor() as cur:
                    cur.execute("SELECT collection_key, payload FROM soulsync_collections;")
                    rows = cur.fetchall()
            if not rows and fallback_seed_file and os.path.exists(fallback_seed_file):
                with open(fallback_seed_file, "r", encoding="utf-8") as f:
                    seed_data = json.load(f)
                ensure_fn(seed_data)
                save_pg_db(seed_data)
                return seed_data
            db = {}
            for key, payload in rows:
                db[key] = payload
            ensure_fn(db)
            return db
        except DatabaseUnavailableError:
            raise
        except Exception as err:
            raise DatabaseUnavailableError(f"PostgreSQL read error: {str(err)[:120]}") from err


def save_pg_db(db):
    """Atomically persist all collections and relational mirror tables inside one transaction."""
    with DB_LOCK:
        try:
            with _connect() as conn:
                with conn.cursor() as cur:
                    for key, val in db.items():
                        cur.execute(
                            """
                            INSERT INTO soulsync_collections (collection_key, payload, updated_at)
                            VALUES (%s, %s::jsonb, NOW())
                            ON CONFLICT (collection_key)
                            DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW();
                            """,
                            (key, json.dumps(val, ensure_ascii=False)),
                        )

                    for u in db.get("users", []):
                        uid = str(u.get("id") or "")
                        email = str(u.get("email") or "").strip().lower()
                        if not uid or not email:
                            continue
                        cur.execute(
                            """
                            INSERT INTO soulsync_users
                                (id, email, name, couple_id, is_verified, is_active, password_hash, invite_code, social_provider, social_account, created_at, updated_at)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
                            ON CONFLICT (id) DO UPDATE SET
                                email = EXCLUDED.email,
                                name = EXCLUDED.name,
                                couple_id = EXCLUDED.couple_id,
                                is_verified = EXCLUDED.is_verified,
                                is_active = EXCLUDED.is_active,
                                password_hash = EXCLUDED.password_hash,
                                invite_code = EXCLUDED.invite_code,
                                social_provider = EXCLUDED.social_provider,
                                social_account = EXCLUDED.social_account,
                                updated_at = NOW();
                            """,
                            (
                                uid,
                                email,
                                str(u.get("name") or "Partner"),
                                u.get("couple_id"),
                                bool(u.get("is_verified", False)),
                                bool(u.get("is_active", True)),
                                u.get("password_hash"),
                                u.get("invite_code"),
                                u.get("social_provider"),
                                u.get("social_account"),
                                u.get("created_at") or datetime.now(timezone.utc).isoformat(),
                            ),
                        )

                    for c in db.get("couples", []):
                        cid = str(c.get("id") or "")
                        if not cid:
                            continue
                        cur.execute(
                            """
                            INSERT INTO soulsync_couples (id, code, p1_id, p2_id, status, created_at, updated_at)
                            VALUES (%s, %s, %s, %s, %s, %s, NOW())
                            ON CONFLICT (id) DO UPDATE SET
                                code = EXCLUDED.code,
                                p1_id = EXCLUDED.p1_id,
                                p2_id = EXCLUDED.p2_id,
                                status = EXCLUDED.status,
                                updated_at = NOW();
                            """,
                            (
                                cid,
                                c.get("code"),
                                c.get("p1_id"),
                                c.get("p2_id"),
                                c.get("status"),
                                c.get("created_at") or datetime.now(timezone.utc).isoformat(),
                            ),
                        )

                    for a in db.get("admins", []):
                        aid = str(a.get("id") or "")
                        aemail = str(a.get("email") or "").strip().lower()
                        if not aid or not aemail:
                            continue
                        cur.execute(
                            """
                            INSERT INTO soulsync_admins (id, email, role, is_active, updated_at)
                            VALUES (%s, %s, %s, %s, NOW())
                            ON CONFLICT (id) DO UPDATE SET
                                email = EXCLUDED.email,
                                role = EXCLUDED.role,
                                is_active = EXCLUDED.is_active,
                                updated_at = NOW();
                            """,
                            (aid, aemail, str(a.get("role") or "Admin"), bool(a.get("is_active", True))),
                        )
                conn.commit()
        except DatabaseUnavailableError:
            raise
        except Exception as err:
            raise DatabaseUnavailableError(f"PostgreSQL write error: {str(err)[:120]}") from err
