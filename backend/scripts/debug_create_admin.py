from fastapi.testclient import TestClient
from src.main import app
import os

client = TestClient(app)
resp = client.post('/auth/token', data={'username':'superbrian','password': os.getenv('TEST_SUPERADMIN_PASSWORD', 'changeme_test_password')})
print('token resp', resp.status_code, resp.text)
if resp.status_code==200:
    token = resp.json()['access_token']
    headers = {'Authorization': f'Bearer {token}'}
    r = client.post('/api/users', json={'username':'admin1','password':'pass','role':'admin'}, headers=headers)
    print('create admin resp', r.status_code, r.text)
