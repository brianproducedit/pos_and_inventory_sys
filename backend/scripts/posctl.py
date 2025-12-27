#!/usr/bin/env python3
"""Simple CLI wrapper for repository maintenance tasks.

Usage:
  python scripts/posctl.py prune-sqlite [--replace]
"""
import argparse
import subprocess
import sys

parser = argparse.ArgumentParser(prog='posctl')
subparsers = parser.add_subparsers(dest='cmd')

prune_parser = subparsers.add_parser('prune-sqlite', help='Create a pruned sqlite DB containing only superadmin')
prune_parser.add_argument('--replace', action='store_true', help='Replace the main sqlite DB with the pruned DB')


def main(argv=None):
    args = parser.parse_args(argv)
    if args.cmd == 'prune-sqlite':
        cmd = ['python', 'scripts/prune_sqlite.py']
        if args.replace:
            cmd.append('--replace')
        try:
            return subprocess.call(cmd)
        except Exception as e:
            print(f'Error running prune_sqlite: {e}')
            return 2
    parser.print_help()
    return 1


if __name__ == '__main__':
    sys.exit(main())