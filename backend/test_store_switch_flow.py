import requests
import os

def main():
    BASE = 'http://localhost:8000'

    r = requests.post(f'{BASE}/auth/token', data={'username':'superbrian','password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')}, headers={'Content-Type': 'application/x-www-form-urlencoded'})
    print('login', r.status_code, r.text)
    if r.status_code != 200:
        raise SystemExit('Auth failed')

    token = r.json()['access_token']
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

    # Create a store
    r = requests.post(f'{BASE}/api/stores', json={'name':'switch-test','location':'nowhere'}, headers=headers)
    print('create store', r.status_code, r.text)
    if r.status_code != 201:
        raise SystemExit('Create store failed')

    sid = r.json().get('id')
    print('created store id', sid)

    # Switch store
    rs = requests.post(f'{BASE}/api/stores/switch/{sid}', headers=headers)
    print('switch resp', rs.status_code, rs.text)

    # Get current user
    ru = requests.get(f'{BASE}/api/users/me', headers=headers)
    print('me', ru.status_code, ru.text)

    # Create product without X-Store-ID header (should use persisted user.store_id)
    rp = requests.post(f'{BASE}/api/products', json={'name':'p1','price':1.0,'stock_quantity':5}, headers=headers)
    print('create product without header', rp.status_code, rp.text)

    # Create product WITH header
    headers_with = headers.copy()
    headers_with['X-Store-ID'] = str(sid)
    rp2 = requests.post(f'{BASE}/api/products', json={'name':'p2','price':1.0,'stock_quantity':5}, headers=headers_with)
    print('create product with header', rp2.status_code, rp2.text)

    # Cleanup: hard delete the store
    rd = requests.delete(f'{BASE}/api/stores/{sid}/hard', headers=headers)
    print('hard delete', rd.status_code, rd.text)


if __name__ == '__main__':
    main()