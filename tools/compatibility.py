#!/usr/bin/env python3
"""Capture reproducible identity; never infer manual acceptance from static checks."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import platform
import sys

from deploy import identity_report
from provenance import write_json


def capture(app, build, install):
    return {**identity_report(app, build, install), 'captured_at': datetime.now(timezone.utc).isoformat(),
            'evidence': 'read_only_observation',
            'host': {'macos': platform.mac_ver()[0], 'architecture': platform.machine()},
            'automated_tests': 'not_run_by_capture',
            'manual_validation': {name: 'pending' for name in
                ('tab', 'sidebar', 'toolbar', 'login_restart', 'save_pdf', 'extensions')},
            'manual_evidence': ''}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--install-dir', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    write_json(Path(args.output), capture(args.app, args.build, args.install_dir))
    print('Observation saved: ' + args.output)
    print('All manual acceptance results are pending. No app/keychain changes made.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
