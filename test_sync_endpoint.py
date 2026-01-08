import requests
import json

# Test the sync/initial endpoint
url = 'http://localhost:8000/api/sync/initial'
headers = {'Authorization': 'Bearer test_token'}

try:
    response = requests.get(url, headers=headers, timeout=5)
    print(f'Status: {response.status_code}')
    if response.status_code == 200:
        data = response.json()
        print('Response keys:', list(data.keys()))
        if 'users' in data:
            print(f'Users count: {len(data["users"])}')
        else:
            print('No users in response')
    else:
        print(f'Response: {response.text[:200]}')
except Exception as e:
    print(f'Error: {e}')