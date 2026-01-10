#!/usr/bin/env python3
"""
Test product creation and sync functionality
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

def test_product_sync_push(token):
    headers = {'Authorization': f'Bearer {token}'}

    # First get a store ID to use
    response = requests.get(f'{BASE_URL}/api/stores', headers=headers)
    if response.status_code != 200:
        print(f"Failed to get stores: {response.status_code}")
        return

    stores = response.json()
    if not stores:
        print("No stores found")
        return

    store_id = stores[0]['id']
    print(f"Using store ID: {store_id}")

    # Test sync push with product creation
    sync_payload = {
        "client_id": "test_client_123",
        "changes": [
            {
                "resource_type": "product",
                "operation": "create",
                "temp_id": "temp_product_001",
                "data": {
                    "name": "Test Product via Sync",
                    "description": "Created via sync push endpoint",
                    "price": 29.99,
                    "stock_quantity": 100,
                    "is_active": True,
                    "store_id": store_id
                }
            }
        ]
    }

    print(f"\nTesting sync push with product creation...")
    response = requests.post(f'{BASE_URL}/api/sync/push',
                           json=sync_payload,
                           headers=headers)
    print(f"Sync push status: {response.status_code}")
    if response.status_code == 200:
        result = response.json()
        print(f"Sync push result: {json.dumps(result, indent=2)}")
    else:
        print(f"Error in sync push: {response.text}")

def test_direct_product_creation(token):
    headers = {'Authorization': f'Bearer {token}'}

    # First get a store ID to use
    response = requests.get(f'{BASE_URL}/api/stores', headers=headers)
    if response.status_code != 200:
        print(f"Failed to get stores: {response.status_code}")
        return

    stores = response.json()
    if not stores:
        print("No stores found")
        return

    store_id = stores[0]['id']
    print(f"Using store ID: {store_id}")

    # Set store context header
    headers['X-Store-ID'] = str(store_id)

    # Test direct product creation
    product_data = {
        "name": "Test Product Direct",
        "description": "Created via direct POST endpoint",
        "price": 19.99,
        "stock_quantity": 50,
        "is_active": True
    }

    print(f"\nTesting direct product creation...")
    response = requests.post(f'{BASE_URL}/api/products',
                           json=product_data,
                           headers=headers)
    print(f"Direct product creation status: {response.status_code}")
    if response.status_code == 201:
        created_product = response.json()
        print(f"Created product: {json.dumps(created_product, indent=2)}")
    else:
        print(f"Error creating product: {response.text}")

if __name__ == '__main__':
    token = login()
    if token:
        test_direct_product_creation(token)
        test_product_sync_push(token)