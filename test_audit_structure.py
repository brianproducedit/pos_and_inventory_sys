#!/usr/bin/env python3
import requests
import json

BASE_URL = 'https://pos-inventory-production.up.railway.app'
USERNAME = 'superadmin'
PASSWORD = 'password'  # Use the password that worked in basic test

def login():
    response = requests.post(f'{BASE_URL}/auth/login', json={
        'username': USERNAME,
        'password': PASSWORD
    })
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        print(f"Login failed: {response.status_code} - {response.text}")
        return None

def get_audit_logs(token):
    headers = {'Authorization': f'Bearer {token}'}
    response = requests.get(f'{BASE_URL}/audit/logs', headers=headers)
    if response.status_code == 200:
        logs = response.json()
        print(f"Total audit logs: {len(logs)}")
        if logs:
            print("First log structure:")
            print(json.dumps(logs[0], indent=2))
        return logs
    else:
        print(f"Failed to get audit logs: {response.status_code} - {response.text}")
        return None

if __name__ == '__main__':
    token = login()
    if token:
        get_audit_logs(token)