import requests
import os


def main():
    r = requests.post('http://localhost:8000/auth/token', data={'username':'superbrian','password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')}, headers={'Content-Type':'application/x-www-form-urlencoded'})
    print('login status', r.status_code)
    if r.status_code != 200:
        print('Token request failed, skipping')
        return
    token = r.json().get('access_token')
    if not token:
        print('No token in response, skipping')
        return
    resp = requests.get('http://localhost:8000/api/users/me', headers={'Authorization':f'Bearer {token}'})
    print('me status', resp.status_code)
    print(resp.json())


if __name__ == '__main__':
    main()