import os
import uuid
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Store, Product, User

def get_token(client, username='superadmin', password='testpw'):
    r = client.post('/auth/token', data={'username': username, 'password': password})
    assert r.status_code == 200, f"Auth failed: {r.text}"
    return r.json()['access_token']

def setup_cross_device_test(tmp_path):
    """Setup database for cross-device testing"""
    db_file = tmp_path / 'test_cross_device.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Create admin user
    from src.init_db import create_admin_user
    create_admin_user()

    # Create store
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    r = client.post('/api/stores', json={'name': 'Cross-Device Store', 'location': 'Test'}, headers=headers)
    assert r.status_code == 201
    store_id = r.json()['id']

    return client, store_id, headers

def test_cross_device_product_creation_consistency(tmp_path):
    """Test that products created on different devices sync consistently"""
    client, store_id, headers = setup_cross_device_test(tmp_path)

    # Simulate Device A creating products
    device_a_changes = [
        {
            'resource_type': 'product',
            'operation': 'create',
            'temp_id': 'a1',
            'data': {
                'name': 'Device A Product 1',
                'price': 10.0,
                'stock_quantity': 100,
                'store_id': store_id
            }
        },
        {
            'resource_type': 'product',
            'operation': 'create',
            'temp_id': 'a2',
            'data': {
                'name': 'Device A Product 2',
                'price': 20.0,
                'stock_quantity': 50,
                'store_id': store_id
            }
        }
    ]

    # Device A syncs
    payload_a = {
        'client_id': 'device-a',
        'changes': device_a_changes
    }

    r_a = client.post('/api/sync/push', json=payload_a, headers=headers)
    assert r_a.status_code == 200
    id_map_a = r_a.json()['id_map']

    # Simulate Device B creating products
    device_b_changes = [
        {
            'resource_type': 'product',
            'operation': 'create',
            'temp_id': 'b1',
            'data': {
                'name': 'Device B Product 1',
                'price': 15.0,
                'stock_quantity': 75,
                'store_id': store_id
            }
        }
    ]

    # Device B syncs
    payload_b = {
        'client_id': 'device-b',
        'changes': device_b_changes
    }

    r_b = client.post('/api/sync/push', json=payload_b, headers=headers)
    assert r_b.status_code == 200
    id_map_b = r_b.json()['id_map']

    # Device C pulls all changes
    r_pull = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert r_pull.status_code == 200
    pull_data = r_pull.json()

    changes = pull_data['changes']
    product_changes = [c for c in changes if c.get('entity_type') == 'product']

    # Should have 3 products total
    assert len(product_changes) == 3

    # Verify all products are present with correct data
    product_names = [c['payload']['data']['name'] for c in product_changes]
    assert 'Device A Product 1' in product_names
    assert 'Device A Product 2' in product_names
    assert 'Device B Product 1' in product_names

    # Verify UUID consistency - same product should have same ID across devices
    # (In real implementation, this would use proper UUIDs)
    product_ids = [c['entity_id'] for c in product_changes]
    assert len(set(product_ids)) == 3  # All IDs should be unique

def test_cross_device_update_conflicts(tmp_path):
    """Test handling of concurrent updates from different devices"""
    client, store_id, headers = setup_cross_device_test(tmp_path)

    # First, create a product
    create_payload = {
        'client_id': 'device-init',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 'init1',
                'data': {
                    'name': 'Conflict Product',
                    'price': 25.0,
                    'stock_quantity': 30,
                    'store_id': store_id
                }
            }
        ]
    }

    r_create = client.post('/api/sync/push', json=create_payload, headers=headers)
    assert r_create.status_code == 200
    server_id = r_create.json()['id_map']['init1']

    # Device A updates the product
    update_a_payload = {
        'client_id': 'device-a',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': server_id,
                'last_updated': (datetime.utcnow() - timedelta(hours=2)).isoformat(),
                'data': {
                    'name': 'Conflict Product - Updated by A',
                    'price': 30.0
                }
            }
        ]
    }

    # Device B also updates the same product (simulating older timestamp)
    update_b_payload = {
        'client_id': 'device-b',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': server_id,
                'last_updated': (datetime.utcnow() - timedelta(hours=1)).isoformat(),
                'data': {
                    'name': 'Conflict Product - Updated by B',
                    'price': 35.0
                }
            }
        ]
    }

    # Device A syncs first
    r_a = client.post('/api/sync/push', json=update_a_payload, headers=headers)
    assert r_a.status_code == 200

    # Device B syncs second - should detect conflict
    r_b = client.post('/api/sync/push', json=update_b_payload, headers=headers)
    assert r_b.status_code == 200

    conflicts = r_b.json().get('conflicts', [])
    assert len(conflicts) > 0, "Should detect update conflict"

    # Verify server has the newer update (Device B's update should win due to newer timestamp)
    db = SessionLocal()
    product = db.query(Product).filter(Product.id == server_id).first()
    assert product is not None
    assert product.name == 'Conflict Product - Updated by B'
    assert product.price == 35.0
    db.close()

def test_cross_device_delete_consistency(tmp_path):
    """Test that deletes sync consistently across devices"""
    client, store_id, headers = setup_cross_device_test(tmp_path)

    # Create products on Device A
    create_payload = {
        'client_id': 'device-a',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 'del1',
                'data': {
                    'name': 'To Be Deleted',
                    'price': 12.0,
                    'stock_quantity': 20,
                    'store_id': store_id
                }
            }
        ]
    }

    r_create = client.post('/api/sync/push', json=create_payload, headers=headers)
    assert r_create.status_code == 200
    server_id = r_create.json()['id_map']['del1']

    # Device B deletes the product
    delete_payload = {
        'client_id': 'device-b',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'delete',
                'id': server_id
            }
        ]
    }

    r_delete = client.post('/api/sync/push', json=delete_payload, headers=headers)
    assert r_delete.status_code == 200

    # Device C pulls changes - should see the delete
    r_pull = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert r_pull.status_code == 200
    pull_data = r_pull.json()

    changes = pull_data['changes']
    delete_changes = [c for c in changes if c.get('operation') == 'delete' and c.get('entity_type') == 'product']

    assert len(delete_changes) == 1
    assert delete_changes[0]['entity_id'] == str(server_id)

    # Verify product is actually deleted from database
    db = SessionLocal()
    product = db.query(Product).filter(Product.id == server_id).first()
    assert product is None, "Product should be deleted"
    db.close()

def test_cross_device_sync_ordering(tmp_path):
    """Test that changes sync in correct order across devices"""
    client, store_id, headers = setup_cross_device_test(tmp_path)

    # Device A: Create product
    create_payload = {
        'client_id': 'device-a',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 'order1',
                'data': {
                    'name': 'Ordered Product',
                    'price': 10.0,
                    'stock_quantity': 10,
                    'store_id': store_id
                }
            }
        ]
    }

    r_create = client.post('/api/sync/push', json=create_payload, headers=headers)
    assert r_create.status_code == 200
    server_id = r_create.json()['id_map']['order1']

    # Device B: Update the product
    update_payload = {
        'client_id': 'device-b',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'update',
                'id': server_id,
                'last_updated': datetime.utcnow().isoformat(),
                'data': {'price': 15.0}
            }
        ]
    }

    r_update = client.post('/api/sync/push', json=update_payload, headers=headers)
    assert r_update.status_code == 200

    # Device C: Delete the product
    delete_payload = {
        'client_id': 'device-c',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'delete',
                'id': server_id
            }
        ]
    }

    r_delete = client.post('/api/sync/push', json=delete_payload, headers=headers)
    assert r_delete.status_code == 200

    # Device D pulls all changes - should be in correct order
    r_pull = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert r_pull.status_code == 200
    pull_data = r_pull.json()

    changes = pull_data['changes']
    product_changes = [c for c in changes if c.get('entity_type') == 'product']

    # Should have create, update, delete in that order
    assert len(product_changes) == 3
    assert product_changes[0]['operation'] == 'create'
    assert product_changes[1]['operation'] == 'update'
    assert product_changes[2]['operation'] == 'delete'

    # Verify server sequences are in order
    seqs = [c['server_seq'] for c in product_changes]
    assert seqs == sorted(seqs), "Server sequences should be in ascending order"

def test_multiple_device_sync_consistency(tmp_path):
    """Test sync consistency with multiple devices operating simultaneously"""
    client, store_id, headers = setup_cross_device_test(tmp_path)

    # Simulate 5 devices each creating 3 products
    all_changes = []
    device_ids = []

    for device_num in range(5):
        device_id = f'device-{device_num}'
        device_ids.append(device_id)

        device_changes = []
        for product_num in range(3):
            device_changes.append({
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': f'{device_id}-p{product_num}',
                'data': {
                    'name': f'Product {device_id}-{product_num}',
                    'price': float(device_num * 10 + product_num),
                    'stock_quantity': (device_num + 1) * (product_num + 1) * 10,
                    'store_id': store_id
                }
            })

        all_changes.extend(device_changes)

        # Each device syncs its changes
        payload = {
            'client_id': device_id,
            'changes': device_changes
        }

        r = client.post('/api/sync/push', json=payload, headers=headers)
        assert r.status_code == 200

    # All devices pull changes - should see all 15 products
    r_pull = client.get('/api/sync/changes?since_seq=0', headers=headers)
    assert r_pull.status_code == 200
    pull_data = r_pull.json()

    changes = pull_data['changes']
    product_changes = [c for c in changes if c.get('entity_type') == 'product' and c.get('operation') == 'create']

    assert len(product_changes) == 15, f"Expected 15 products, got {len(product_changes)}"

    # Verify no duplicate products
    product_names = [c['payload']['data']['name'] for c in product_changes]
    assert len(set(product_names)) == 15, "Should have 15 unique product names"

    # Verify all expected products are present
    for device_id in device_ids:
        for product_num in range(3):
            expected_name = f'Product {device_id}-{product_num}'
            assert expected_name in product_names, f"Missing product: {expected_name}"
