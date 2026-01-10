#!/usr/bin/env python3
"""
Detailed test of Railway backend audit logs
"""

import requests

base_url = 'https://backend-production-5388.up.railway.app'

# Login first
login_response = requests.post(f'{base_url}/auth/token',
                             data={'username': 'superadmin', 'password': 'bk007bang'},
                             headers={'Content-Type': 'application/x-www-form-urlencoded'})

if login_response.status_code == 200:
    token = login_response.json()['access_token']
    headers = {'Authorization': f'Bearer {token}'}

    print('✅ Login successful')

    # Get audit logs without store filter
    audit_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=2', headers=headers)
    print('\nAudit logs (no store filter):')
    if audit_response.status_code == 200:
        data = audit_response.json()
        print(f'  Total: {data["total_count"]}')
        for log in data['logs']:
            print(f'  - {log["action"]} by {log.get("username", "unknown")} (store_id: {log.get("store_id")})')

    # Get audit logs with store filter
    audit_store_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=2&store_id=24', headers=headers)
    print('\nAudit logs (store_id=24):')
    if audit_store_response.status_code == 200:
        data = audit_store_response.json()
        print(f'  Total: {data["total_count"]}')
        for log in data['logs']:
            print(f'  - {log["action"]} by {log.get("username", "unknown")} (store_id: {log.get("store_id")})')

    print('\n✅ Railway backend verification complete!')
else:
    print(f'❌ Login failed: {login_response.status_code}')