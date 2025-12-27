import requests
import os

if __name__ == "__main__":
    login = requests.post('http://localhost:8000/auth/token', data={'username':'superbrian','password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')}, headers={'Content-Type':'application/x-www-form-urlencoded'})
    print('login', login.status_code)
    if login.status_code==200:
        token = login.json()['access_token']
        headers={'Authorization':f'Bearer {token}'}
        # create store
        r = requests.post('http://localhost:8000/api/stores', json={'name':'temporary','location':'nowhere'}, headers=headers)
        print('create', r.status_code, r.text)
        if r.status_code==201:
            sid = r.json()['id']
            # create product for store
            rp = requests.post('http://localhost:8000/api/products', json={'name':'temp','price':1.0,'stock_quantity':10,'store_id':sid}, headers=headers)
            print('create product', rp.status_code, rp.text)
            # now hard delete
            rd = requests.delete(f'http://localhost:8000/api/stores/{sid}/hard', headers=headers)
            print('hard delete', rd.status_code, rd.text)
