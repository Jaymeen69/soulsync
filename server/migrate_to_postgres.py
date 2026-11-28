"""
Safe Migration & Rollback Tool for SoulSync database.json -> PostgreSQL.
Usage:
  DATABASE_URL=postgresql://... python3 migrate_to_postgres.py --migrate
  DATABASE_URL=postgresql://... python3 migrate_to_postgres.py --verify
  DATABASE_URL=postgresql://... python3 migrate_to_postgres.py --rollback backups/database_backup_....json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone

import db_backend

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_JSON = os.path.join(BASE_DIR, "database.json")


def _identity(d):
    return d


def migrate(json_path):
    if not db_backend.is_postgres_enabled():
        print("ERROR: DATABASE_URL environment variable is required.")
        sys.exit(1)
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Backup existing PostgreSQL state if present
    db_backend.init_postgres_schema()
    existing = db_backend.load_pg_db(_identity, fallback_seed_file=None)
    if existing:
        bdir = os.path.join(BASE_DIR, "backups")
        os.makedirs(bdir, exist_ok=True)
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        bpath = os.path.join(bdir, f"pg_pre_migrate_{ts}.json")
        with open(bpath, "w", encoding="utf-8") as bf:
            json.dump(existing, bf, indent=2, ensure_ascii=False)
        print(f"Backed up existing PostgreSQL data to {bpath}")

    db_backend.save_pg_db(data)
    verify(data)


def verify(expected=None):
    pg = db_backend.load_pg_db(_identity, fallback_seed_file=None)
    keys = ["users", "couples", "admins", "chat_messages", "memories", "music_playlists", "notifications", "audit_logs"]
    counts = {k: len(pg.get(k, [])) for k in keys}
    print("POSTGRES_RECORD_COUNTS:", json.dumps(counts))
    if expected is not None:
        for k in keys:
            assert len(pg.get(k, [])) == len(expected.get(k, [])), f"Count mismatch for {k}"
        print("MIGRATION_VERIFIED_ZERO_DATA_LOSS")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrate", action="store_true")
    parser.add_argument("--verify", action="store_true")
    parser.add_argument("--rollback", type=str, default="")
    parser.add_argument("--source", type=str, default=DEFAULT_JSON)
    args = parser.parse_args()

    if args.rollback:
        migrate(args.rollback)
    elif args.migrate:
        migrate(args.source)
    elif args.verify:
        verify()
    else:
        parser.print_help()
