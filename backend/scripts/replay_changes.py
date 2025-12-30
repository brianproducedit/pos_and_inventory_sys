#!/usr/bin/env python3
"""CLI utility to replay changes between server_seq ranges."""
import argparse
from src.database import SessionLocal
from src.services.sync_replay import replay_changes


def main():
    p = argparse.ArgumentParser(description='Replay change log entries by server_seq range')
    p.add_argument('--from', dest='from_seq', type=int, required=True, help='Start server_seq (inclusive)')
    p.add_argument('--to', dest='to_seq', type=int, required=True, help='End server_seq (inclusive)')
    p.add_argument('--dry-run', dest='dry_run', action='store_true', help='Do not apply changes')
    p.add_argument('--entity', dest='entity_type', type=str, required=False, help='Optional entity_type filter (e.g., product, store)')
    args = p.parse_args()

    db = SessionLocal()
    try:
        report = replay_changes(db, args.from_seq, args.to_seq, dry_run=args.dry_run, entity_type=args.entity_type)
        print('Replay report:')
        print(f"Processed {report.get('processed')} changes (applied={report.get('applied')}, skipped={report.get('skipped')})")
        for r in report.get('report', []):
            print(r)
        if report.get('errors'):
            print('Errors:')
            for e in report.get('errors'):
                print(e)
    finally:
        db.close()


if __name__ == '__main__':
    main()
