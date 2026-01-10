#!/usr/bin/env python3
"""
Test store creation and sync functionality
"""

import requests
import json

BASE_URL = 'https://backend-production-5388.up.railway.app'
USERNAME = 'superadmin'
PASSWORD = 'bk007bang'

def login():
    response = requests.post(f'{BASE_URL}/auth/token',
                           data={'username': USERNAME, 'password': PASSWORD},
                           headers={'Content-Type': 'application/x-www-form-urlencoded'})
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        print(f"Login failed: {response.status_code}")
        return None

def test_stores_api(token):
    headers = {'Authorization': f'Bearer {token}'}

    # Get existing stores
    response = requests.get(f'{BASE_URL}/api/stores', headers=headers)
    print(f"Get stores status: {response.status_code}")
    if response.status_code == 200:
        stores = response.json()
        print(f"Existing stores: {len(stores)}")
        for store in stores:
            print(f"  - {store.get('name')} (ID: {store.get('id')})")

    # Try to create a test store
    test_store_data = {
        'name': 'Test Store API',
        'address': '123 Test Street',
        'phone': '555-0123',
        'email': 'test@example.com'
    }

    print(f"\nCreating test store: {test_store_data['name']}")
    response = requests.post(f'{BASE_URL}/api/stores',
                           json=test_store_data,
                           headers=headers)
    print(f"Create store status: {response.status_code}")
    if response.status_code == 200:
        created_store = response.json()
        print(f"Created store: {created_store}")
        return created_store.get('id')
    else:
        print(f"Error creating store: {response.text}")
        return None

def test_sync_queue(token):
    headers = {'Authorization': f'Bearer {token}'}

    # Check sync queue
    response = requests.get(f'{BASE_URL}/api/sync/queue', headers=headers)
    print(f"\nSync queue status: {response.status_code}")
    if response.status_code == 200:
        queue = response.json()
        print(f"Sync queue items: {len(queue)}")
        for item in queue[:3]:  # Show first 3
            print(f"  - {item}")
    else:
        print(f"Error getting sync queue: {response.text}")

if __name__ == '__main__':
    token = login()
    if token:
        test_stores_api(token)
        test_sync_queue(token)