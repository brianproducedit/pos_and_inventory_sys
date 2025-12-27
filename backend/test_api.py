#!/usr/bin/env python3
import requests

# Test the products endpoint
url = 'http://localhost:8000/api/products'
headers = {'Authorization': 'Bearer fake_token'}

try:
    response = requests.get(url, headers=headers)
    print(f'Status: {response.status_code}')
    if response.status_code == 401:
        print('401 Unauthorized (expected with fake token)')
    elif response.status_code == 200:
        data = response.json()
        print(f'Products returned: {len(data)}')
        for p in data[:3]:  # Show first 3
            print(f'  - {p.get("name")}: active={p.get("is_active")}')
except Exception as e:
    print(f'Error: {e}')