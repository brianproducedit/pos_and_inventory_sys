#!/usr/bin/env python3
"""
Test Railway backend audit logs API
"""

import requests
import json

# Test Railway backend
base_url = 'https://backend-production-5388.up.railway.app'

print('Testing Railway Backend...')
print(f'Base URL: {base_url}')

# First, try to login to get a token
try:
    login_response = requests.post(f'{base_url}/auth/token',
                                 data={'username': 'superadmin', 'password': 'bk007bang'},
                                 headers={'Content-Type': 'application/x-www-form-urlencoded'},
                                 timeout=10)

    print(f'Login Status: {login_response.status_code}')

    if login_response.status_code == 200:
        token = login_response.json()['access_token']
        headers = {'Authorization': f'Bearer {token}'}

        # Test audit logs endpoint
        audit_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=3',
                                    headers=headers, timeout=10)

        print(f'Audit Logs Status: {audit_response.status_code}')

        if audit_response.status_code == 200:
            data = audit_response.json()
            print('✅ Audit logs API working!')
            print(f'   Total logs: {data.get("total_count", 0)}')
            logs = data.get('logs', [])
            print(f'   Returned logs: {len(logs)}')

            # Test with store_id parameter
            audit_with_store = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=3&store_id=24',
                                          headers=headers, timeout=10)
            print(f'Audit Logs with store_id Status: {audit_with_store.status_code}')

            if audit_with_store.status_code == 200:
                print('✅ Store filtering parameter working!')
            else:
                print('❌ Store filtering parameter failed')
        else:
            print(f'❌ Audit logs API failed: {audit_response.text[:200]}')
    else:
        print(f'❌ Login failed: {login_response.text[:200]}')

except requests.exceptions.RequestException as e:
    print(f'❌ Network error: {e}')
except Exception as e:
    print(f'❌ Error: {e}')