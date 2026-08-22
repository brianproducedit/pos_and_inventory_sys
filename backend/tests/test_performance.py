import os
import time
import pytest
from datetime import datetime, timedelta
from fastapi.testclient import TestClient
from src.main import app
from src.database import SessionLocal
from src.models import Store, Product, User
from src.auth import get_password_hash

def get_token(client, username='superadmin', password='testpw'):
    r = client.post('/auth/token', data={'username': username, 'password': password})
    assert r.status_code == 200, f"Auth failed: {r.text}"
    return r.json()['access_token']

@pytest.fixture
def setup_large_dataset(tmp_path):
    """Setup a large dataset for performance testing"""
    db_file = tmp_path / 'test_performance.db'
    os.environ['DATABASE_URL'] = f"sqlite:///{db_file}"
    os.environ['DEFAULT_SUPERADMIN_PASSWORD'] = 'testpw'

    client = TestClient(app)

    # Create admin user
    from src.init_db import create_admin_user
    create_admin_user()

    # Create store
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    r = client.post('/api/stores', json={'name': 'Performance Store', 'location': 'Test'}, headers=headers)
    assert r.status_code == 201
    store_id = r.json()['id']

    # Create 1000 products
    products = []
    for i in range(1000):
        product_data = {
            'name': f'Product {i}',
            'description': f'Description for product {i}',
            'price': float(i + 1),
            'stock_quantity': i * 10,
            'store_id': store_id
        }
        products.append(product_data)

    # Insert products directly for speed
    db = SessionLocal()
    for product_data in products:
        product = Product(**product_data)
        db.add(product)
    db.commit()
    db.close()

    return client, store_id, headers

def test_sync_push_performance_large_batch(setup_large_dataset):
    """Test performance of pushing a large batch of changes"""
    client, store_id, headers = setup_large_dataset

    # Create 100 product changes
    changes = []
    for i in range(100):
        changes.append({
            'resource_type': 'product',
            'operation': 'create',
            'temp_id': f'temp_{i}',
            'data': {
                'name': f'New Product {i}',
                'description': f'New description {i}',
                'price': float(i + 100),
                'stock_quantity': i * 5,
                'store_id': store_id
            }
        })

    payload = {
        'client_id': 'perf-test-client',
        'changes': changes
    }

    # Measure sync push performance
    start_time = time.time()
    r = client.post('/api/sync/push', json=payload, headers=headers)
    end_time = time.time()

    assert r.status_code == 200, r.text

    duration = end_time - start_time
    print(f"Sync push of 100 changes took {duration:.2f} seconds")

    # Should complete within 2 seconds for 100 changes
    assert duration < 2.0, f"Sync push too slow: {duration:.2f} seconds"

def test_sync_pull_performance_large_dataset(setup_large_dataset):
    """Test performance of pulling changes from a large dataset"""
    client, store_id, headers = setup_large_dataset

    # Pull all changes
    start_time = time.time()
    r = client.get('/api/sync/changes?since_seq=0', headers=headers)
    end_time = time.time()

    assert r.status_code == 200, r.text

    duration = end_time - start_time
    data = r.json()
    changes_count = len(data.get('changes', []))

    print(f"Sync pull returned {changes_count} changes in {duration:.2f} seconds")

    # Should complete within 1 second for 1000 products
    assert duration < 1.0, f"Sync pull too slow: {duration:.2f} seconds"
    assert changes_count >= 1000

def test_products_api_performance_pagination(setup_large_dataset):
    """Test performance of products API with pagination"""
    client, store_id, headers = setup_large_dataset

    # Test getting first page
    start_time = time.time()
    r = client.get(f'/api/stores/{store_id}/products?page=1&per_page=50', headers=headers)
    end_time = time.time()

    assert r.status_code == 200, r.text

    duration = end_time - start_time
    data = r.json()

    print(f"Products API pagination took {duration:.2f} seconds, returned {len(data.get('items', []))} items")

    # Should complete within 0.5 seconds
    assert duration < 0.5, f"Products API too slow: {duration:.2f} seconds"
    assert len(data.get('items', [])) == 50

def test_sales_api_performance_date_range(setup_large_dataset):
    """Test performance of sales API with date range filtering"""
    client, store_id, headers = setup_large_dataset

    # Create some sales data
    db = SessionLocal()
    from src.models import Sale

    sales_data = []
    base_date = datetime.utcnow() - timedelta(days=30)
    for i in range(500):
        sale = Sale(transaction_number="TX-TEST", 
            product_name=f'Product {i % 100}',
            quantity=i % 10 + 1,
            unit_price=float((i % 100) + 1),
            total=float(((i % 10) + 1) * ((i % 100) + 1)),
            store_id=store_id,
            created_at=base_date + timedelta(days=i % 30)
        )
        sales_data.append(sale)

    for sale in sales_data:
        db.add(sale)
    db.commit()
    db.close()

    # Query sales for last 7 days
    start_date = (datetime.utcnow() - timedelta(days=7)).date().isoformat()
    end_date = datetime.utcnow().date().isoformat()

    start_time = time.time()
    r = client.get(f'/api/stores/{store_id}/sales?start_date={start_date}&end_date={end_date}', headers=headers)
    end_time = time.time()

    assert r.status_code == 200, r.text

    duration = end_time - start_time
    data = r.json()

    print(f"Sales API date range query took {duration:.2f} seconds, returned {len(data)} items")

    # Should complete within 0.5 seconds
    assert duration < 0.5, f"Sales API too slow: {duration:.2f} seconds"

def test_analytics_performance_summary(setup_large_dataset):
    """Test performance of analytics summary calculation"""
    client, store_id, headers = setup_large_dataset

    # Create sales data for analytics
    db = SessionLocal()
    from src.models import Sale

    sales_data = []
    for i in range(1000):
        sale = Sale(transaction_number="TX-TEST", 
            product_name=f'Product {i % 100}',
            quantity=1,
            unit_price=10.0,
            total=10.0,
            store_id=store_id,
            created_at=datetime.utcnow() - timedelta(days=i % 30)
        )
        sales_data.append(sale)

    for sale in sales_data:
        db.add(sale)
    db.commit()
    db.close()

    # Get analytics summary
    start_time = time.time()
    r = client.get(f'/api/stores/{store_id}/analytics/summary', headers=headers)
    end_time = time.time()

    assert r.status_code == 200, r.text

    duration = end_time - start_time
    data = r.json()

    print(f"Analytics summary took {duration:.2f} seconds")

    # Should complete within 1 second
    assert duration < 1.0, f"Analytics summary too slow: {duration:.2f} seconds"
    assert 'total_sales' in data
    assert 'total_items_sold' in data

def test_concurrent_requests_performance(setup_large_dataset):
    """Test performance under concurrent requests"""
    import threading

    client, store_id, headers = setup_large_dataset
    results = []
    errors = []

    def make_request(thread_id):
        try:
            start_time = time.time()
            r = client.get(f'/api/stores/{store_id}/products?page=1&per_page=10', headers=headers)
            end_time = time.time()

            results.append({
                'thread_id': thread_id,
                'status_code': r.status_code,
                'duration': end_time - start_time
            })
        except Exception as e:
            errors.append(f"Thread {thread_id}: {str(e)}")

    # Make 10 concurrent requests
    threads = []
    for i in range(10):
        t = threading.Thread(target=make_request, args=(i,))
        threads.append(t)
        t.start()

    # Wait for all threads to complete
    for t in threads:
        t.join()

    # Check results
    assert len(errors) == 0, f"Concurrent request errors: {errors}"
    assert len(results) == 10

    # All requests should succeed
    for result in results:
        assert result['status_code'] == 200, f"Request {result['thread_id']} failed"

    # Average response time should be reasonable
    avg_duration = sum(r['duration'] for r in results) / len(results)
    print(f"Average concurrent request duration: {avg_duration:.2f} seconds")

    # Should complete within 1 second on average
    assert avg_duration < 1.0, f"Concurrent requests too slow: {avg_duration:.2f} seconds"
