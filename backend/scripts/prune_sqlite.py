#!/usr/bin/env python3
"""Create a sanitized sqlite database containing only the default superadmin user.

Usage:
  python scripts/prune_sqlite.py [--replace]

By default, this script creates `pos_inventory.pruned.db` in the current directory. Pass
`--replace` to replace the configured sqlite file (use with caution).
"""

import os
import shutil
import argparse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from src.models import Base, User, UserRole
from src.auth import get_password_hash
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///pos_inventory.db')
parser = argparse.ArgumentParser()
parser.add_argument('--replace', action='store_true', help='Replace the configured sqlite DB with the pruned DB')
args = parser.parse_args()

if not DATABASE_URL.startswith('sqlite'):
    print('This script is intended for sqlite databases only. Set DATABASE_URL to a sqlite URL to proceed.')
    raise SystemExit(1)

# Determine file path
if DATABASE_URL.startswith('sqlite:///'):
    db_path = DATABASE_URL.replace('sqlite:///', '')
else:
    print('Unexpected sqlite URL format. Expecting sqlite:///path/to/db')
    raise SystemExit(1)

pruned_path = os.path.splitext(db_path)[0] + '.pruned.db'
pruned_url = f'sqlite:///{pruned_path}'

print(f'Creating pruned DB at: {pruned_path}')

# Create pruned DB with full schema
engine = create_engine(pruned_url, connect_args={'check_same_thread': False})
Base.metadata.create_all(bind=engine)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Seed default superadmin
default_username = os.getenv('DEFAULT_SUPERADMIN_USERNAME', 'superadmin')
default_password = os.getenv('DEFAULT_SUPERADMIN_PASSWORD')
if not default_password:
    import secrets
    default_password = secrets.token_urlsafe(12)
    print('Generated a temporary DEFAULT_SUPERADMIN_PASSWORD for pruned DB.')

with SessionLocal() as db:
    admin = User(
        username=default_username,
        password_hash=get_password_hash(default_password),
        role=UserRole.superadmin,
        must_change_password=True,
    )
    db.add(admin)
    db.commit()

print('Pruned DB created and superadmin seeded:')
print(f'  username: {default_username}')
print('  Note: password is the value from DEFAULT_SUPERADMIN_PASSWORD env var or a generated temporary password.')

if args.replace:
    backup_path = db_path + '.backup'
    print(f'Replacing original DB. Backing up original to {backup_path}')
    shutil.copyfile(db_path, backup_path)
    shutil.copyfile(pruned_path, db_path)
    print('Replacement complete. Original backed up.')

print('Done.')