import requests

s = requests.Session()
s.trust_env = False

print('Logging in via /auth/token (form)')
resp = s.post('http://127.0.0.1:8000/auth/token', data={'username':'superadmin','password':'bk007bang'})
print('Login status', resp.status_code)
print('Body:', resp.text[:500])

if resp.status_code == 200:
    token = resp.json()['access_token']
    headers = {'Authorization': f'Bearer {token}'}
    r = s.get('http://127.0.0.1:8000/api/audit-logs?skip=0&limit=5', headers=headers)
    print('Audit logs status', r.status_code)
    try:
        data = r.json()
        print('Total:', data.get('total_count'))
        print('Logs keys sample:', [list(log.keys()) for log in data.get('logs', [])[:1]])
        if data.get('logs'):
            print('First log:', data['logs'][0])
    except Exception as e:
        print('Failed to parse JSON:', e)
else:
    print('Login failed')