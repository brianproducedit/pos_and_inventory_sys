#!/usr/bin/env python3
"""
Check audit log structure
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

    # Get audit logs with full details
    audit_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=20', headers=headers)
    if audit_response.status_code == 200:
        data = audit_response.json()
        print(f"Response keys: {list(data.keys())}")
        print(f"Response structure: {type(data)}")
        if isinstance(data, list):
            print(f"Total audit logs: {len(data)}")
            print('\nFirst 5 audit logs:')
            for i, log in enumerate(data[:5]):
                print(f'\nLog {i+1}:')
                for key, value in log.items():
                    print(f'  {key}: {value}')
        elif isinstance(data, dict) and 'logs' in data:
            print(f"Total audit logs: {data.get('total', len(data['logs']))}")
            print(f"Returned logs: {len(data['logs'])}")
            if data['logs']:
                print('\nFirst 5 audit logs:')
                for i, log in enumerate(data['logs'][:5]):
                    print(f'\nLog {i+1}:')
                    for key, value in log.items():
                        print(f'  {key}: {value}')
            else:
                print('No audit logs found')
        else:
            print(f'Unexpected response format: {data}')
    else:
        print(f'API error: {audit_response.status_code}')

    # Test store filtering
    print('\n--- Testing Store Filtering ---')
    # Test with store_id=1
    filter_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=20&store_id=1', headers=headers)
    if filter_response.status_code == 200:
        filter_data = filter_response.json()
        print(f"Logs with store_id=1: {len(filter_data['logs'])}")
        if filter_data['logs']:
            print('Sample filtered log:')
            for key, value in filter_data['logs'][0].items():
                print(f'  {key}: {value}')
    else:
        print(f'Filter API error: {filter_response.status_code}')

    # Test with store_id=None (should return all)
    none_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=20&store_id=None', headers=headers)
    if none_response.status_code == 200:
        none_data = none_response.json()
        print(f"Logs with store_id=None: {len(none_data['logs'])}")
    else:
        print(f'None filter API error: {none_response.status_code}')

    # Test without store_id parameter (should return all)
    all_response = requests.get(f'{base_url}/api/audit-logs?skip=0&limit=20', headers=headers)
    if all_response.status_code == 200:
        all_data = all_response.json()
        print(f"All logs (no filter): {len(all_data['logs'])}")
    else:
        print(f'All logs API error: {all_response.status_code}')
else:
    print(f'Login failed: {login_response.status_code}')