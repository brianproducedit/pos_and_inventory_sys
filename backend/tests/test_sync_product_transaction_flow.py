import importlib
from fastapi.testclient import TestClient
from src.models import Store, Product, Sale, SaleItem
from tests.test_replay import get_token


from tests.test_sync_integration import _setup_app


def test_push_transaction_with_temp_product(tmp_path):
    client, SessionLocal = _setup_app(tmp_path)
    token = get_token(client)
    headers = {'Authorization': f'Bearer {token}'}

    db = SessionLocal()
    store = Store(name='IntegrationStoreTx')
    db.add(store)
    db.commit()
    db.refresh(store)

    payload = {
        'client_id': 'cid-tx-1',
        'changes': [
            {
                'resource_type': 'product',
                'operation': 'create',
                'temp_id': 'tprod',
                'data': {
                    'name': 'Sauce 500ml',
                    'sku': 'S500',
                    'price': 0.5,
                    'stock_quantity': 28,
                    'store_id': store.id,
                }
            },
            {
                'resource_type': 'transaction',
                'operation': 'create',
                'temp_id': 'ttxn',
                'data': {
                    'total_amount': 10.0,
                    'payment_method': 'cash',
                    'store_id': store.id,
                    'items': [
                        {'product_id': 'tprod', 'quantity': 2, 'unit_price': 5.0, 'total_price': 10.0}
                    ]
                }
            }
        ]
    }

    r = client.post('/api/sync/push', json=payload, headers=headers)
    assert r.status_code == 200, r.text
    j = r.json()

    # id_map should contain mapping for both temp ids
    assert 'tprod' in j.get('id_map', {}), j
    assert 'ttxn' in j.get('id_map', {}), j

    server_prod_id = j['id_map']['tprod']
    server_txn_id = j['id_map']['ttxn']

    # Confirm product exists on server
    p = db.query(Product).filter(Product.id == server_prod_id).first()
    assert p is not None
    assert p.name == 'Sauce 500ml'

    # Confirm sale exists on server and references the product
    s = db.query(Sale).filter(Sale.id == server_txn_id).first()
    assert s is not None
    items = db.query(SaleItem).filter(SaleItem.sale_id == s.id).all()
    assert len(items) == 1
    assert items[0].product_id == p.id
