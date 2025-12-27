import requests
import json
import os

if __name__ == "__main__":
    # Login as superadmin using form data
    login_data = {
        'username': 'superbrian',
        'password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')
    }

    response = requests.post('http://localhost:8000/auth/token', 
                            data=login_data,
                            headers={'Content-Type': 'application/x-www-form-urlencoded'})
    print('Login response status:', response.status_code)
    print('Login response text:', response.text)
    if response.status_code == 200:
        token = response.json()['access_token']
        print('Login successful')

        # Test getting stores
        headers = {'Authorization': f'Bearer {token}'}
        stores_response = requests.get('http://localhost:8000/api/stores', headers=headers)
        print('GET /api/stores status:', stores_response.status_code)
        if stores_response.status_code == 200:
            stores = stores_response.json()
            print('Stores returned:', len(stores))
            for store in stores[:3]:  # Show first 3
                print(f'  ID: {store["id"]}, Name: {store["name"]}, Active: {store["is_active"]}')
        else:
            print('Error:', stores_response.text)

        # Test current user info
        me_response = requests.get('http://localhost:8000/api/users/me', headers=headers)
        print('GET /api/users/me status:', me_response.status_code)
        if me_response.status_code == 200:
            me = me_response.json()
            print('User role:', me.get('role'))
        else:
            print('Error fetching user info:', me_response.text)

        # Test creating a store
        create_data = {
            'name': 'Test Store',
            'location': 'Test Location'
        }
        create_response = requests.post('http://localhost:8000/api/stores', json=create_data, headers=headers)
        print('POST /api/stores status:', create_response.status_code)
        if create_response.status_code == 201:
            new_store = create_response.json()
            print('Created store:', new_store['name'])
        else:
            print('Create error:', create_response.text)

    else:
        print('Login failed:', response.status_code, response.text)