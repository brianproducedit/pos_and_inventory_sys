#!/usr/bin/env python3
"""
Comprehensive Railway Backend Health Check
"""

import requests
import json

BASE_URL = 'https://backend-production-5388.up.railway.app'
USERNAME = 'superadmin'
PASSWORD = 'bk007bang'

def test_endpoint(name, method='GET', url='', headers=None, expected_status=200):
    """Test an API endpoint and return result"""
    try:
        if method == 'GET':
            response = requests.get(f'{BASE_URL}{url}', headers=headers or {})
        elif method == 'POST':
            response = requests.post(f'{BASE_URL}{url}', headers=headers or {}, json={})
        else:
            return False, f"Unsupported method: {method}"

        if response.status_code == expected_status:
            return True, f"✅ {name}: {response.status_code}"
        else:
            return False, f"❌ {name}: {response.status_code} (expected {expected_status})"
    except Exception as e:
        return False, f"❌ {name}: Error - {str(e)}"

def main():
    print("🚀 Railway Backend Comprehensive Health Check")
    print("=" * 50)

    # Test basic endpoints
    results = []

    # Health check
    success, msg = test_endpoint("Health Check", "GET", "/health")
    results.append((success, msg))

    # Root endpoint
    success, msg = test_endpoint("Root Endpoint", "GET", "/")
    results.append((success, msg))

    # Docs endpoint
    success, msg = test_endpoint("API Docs", "GET", "/docs")
    results.append((success, msg))

    # Login to get token
    try:
        login_response = requests.post(f'{BASE_URL}/auth/token', data={
            'username': USERNAME,
            'password': PASSWORD
        }, headers={'Content-Type': 'application/x-www-form-urlencoded'})
        if login_response.status_code == 200:
            token = login_response.json()['access_token']
            headers = {'Authorization': f'Bearer {token}'}
            results.append((True, "✅ Authentication: 200"))

            # Test authenticated endpoints
            success, msg = test_endpoint("User Profile", "GET", "/api/auth/me", headers)
            results.append((success, msg))

            success, msg = test_endpoint("Audit Logs", "GET", "/api/audit-logs", headers)
            results.append((success, msg))

            # Test stores endpoint
            success, msg = test_endpoint("Stores List", "GET", "/api/stores", headers)
            results.append((success, msg))

            # Test products endpoint
            success, msg = test_endpoint("Products List", "GET", "/api/products", headers)
            results.append((success, msg))

        else:
            results.append((False, f"❌ Authentication: {login_response.status_code}"))
    except Exception as e:
        results.append((False, f"❌ Authentication: Error - {str(e)}"))

    # Print results
    print("\n📊 Test Results:")
    print("-" * 30)
    all_passed = True
    for success, msg in results:
        print(msg)
        if not success:
            all_passed = False

    print("\n" + "=" * 50)
    if all_passed:
        print("🎉 ALL TESTS PASSED - Railway Backend is working properly!")
    else:
        print("⚠️  Some tests failed - Check the backend status")

    return all_passed

if __name__ == '__main__':
    main()