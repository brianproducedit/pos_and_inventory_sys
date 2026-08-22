#!/usr/bin/env python3
"""Simple smoke test for backend.

Environment variables:
- BASE_URL (default http://localhost:8000)
- SUPERADMIN_USERNAME (default superadmin)
- SUPERADMIN_PASSWORD (default bk007bang)

Exit code 0 on success, 1 on failure.
"""
import os
import sys
import requests


def main():
    # When running locally behind a corporate proxy, ensure local calls bypass the proxy
    for _k in ('HTTP_PROXY','http_proxy','HTTPS_PROXY','https_proxy'):
        os.environ.pop(_k, None)

    BASE_URL = os.getenv('BASE_URL', 'http://localhost:8000').rstrip('/')
    # Prefer non-empty env vars; treat empty string as missing so CI secrets can be optional
    USERNAME = os.getenv('SUPERADMIN_USERNAME') or os.getenv('DEFAULT_SUPERADMIN_USERNAME') or 'superadmin'
    PASSWORD = os.getenv('SUPERADMIN_PASSWORD') or os.getenv('DEFAULT_SUPERADMIN_PASSWORD') or 'bk007bang'

    session = requests.Session()
    session.trust_env = False  # ignore system proxy settings for local checks

    try:
        print(f"Checking {BASE_URL}/health")
        r = session.get(f"{BASE_URL}/health", timeout=5)
        r.raise_for_status()
        data = r.json()
        if data.get('status') != 'ok':
            print('Health check returned unexpected body:', data)
            sys.exit(1)
        print('Health OK')

        print('Requesting token')
        token_resp = session.post(f"{BASE_URL}/auth/token", data={'username': USERNAME, 'password': PASSWORD}, timeout=5)
        if token_resp.status_code != 200:
            print('Token request failed:', token_resp.status_code, token_resp.text)
            sys.exit(1)
        token_json = token_resp.json()
        access_token = token_json.get('access_token')
        if not access_token:
            print('No access_token in response:', token_json)
            sys.exit(1)
        print('Token obtained')

        # Try /api/users/me if available
        me_url = f"{BASE_URL}/api/users/me"
        print(f'Checking {me_url}')
        me = session.get(me_url, headers={'Authorization': f'Bearer {access_token}'}, timeout=5)
        if me.status_code == 200:
            me_json = me.json()
            print('User info:', {k: me_json.get(k) for k in ['username', 'must_change_password']})
        else:
            print(f'{me_url} returned {me.status_code}, skipping detailed user checks')

        print('Smoke test passed')
        return 0

    except Exception as e:
        print('Smoke test failed:', e)
        return 1


if __name__ == '__main__':
    sys.exit(main())
