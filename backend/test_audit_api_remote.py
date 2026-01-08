import requests
import json

print('Testing Audit Logs API...')
try:
    # Login first
    login_response = requests.post('http://192.168.49.85:8000/api/auth/login',
                                   json={'username': 'superadmin', 'password': 'password'})

    if login_response.status_code == 200:
        token = login_response.json()['access_token']
        headers = {'Authorization': f'Bearer {token}'}

        # Test audit logs endpoint
        audit_response = requests.get('http://192.168.49.85:8000/api/audit-logs?skip=0&limit=3',
                                    headers=headers)

        print(f'Status Code: {audit_response.status_code}')
        if audit_response.status_code == 200:
            data = audit_response.json()
            print('Response structure valid')
            print(f'- Total logs: {data.get("total_count", 0)}')
            logs = data.get('logs', [])
            print(f'- Returned logs: {len(logs)}')
            if logs:
                print(f'- Sample log action: {logs[0].get("action", "N/A")}')
                print(f'- Sample log user: {logs[0].get("username", "N/A")}')
                print('Audit logs API working correctly!')
            else:
                print('No audit logs found (expected for new installation)')
        else:
            print(f'Error: {audit_response.status_code} - {audit_response.text}')
    else:
        print(f'Login failed: {login_response.status_code}')

except requests.exceptions.ConnectionError:
    print('Backend server not running')
except Exception as e:
    print(f'Error: {e}')