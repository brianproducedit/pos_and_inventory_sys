"""add_ondelete_cascade_user_stores

Revision ID: c2b7f4d6e59a
Revises: faef9c653d40
Create Date: 2025-12-25 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers, used by Alembic.
revision: str = 'c2b7f4d6e59a'
down_revision: Union[str, Sequence[str], None] = 'faef9c653d40'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _find_fk_name_on_stores(inspector):
    fks = inspector.get_foreign_keys('user_stores')
    for fk in fks:
        # constrained_columns can be list like ['store_id']
        if fk.get('referred_table') == 'stores' and 'store_id' in fk.get('constrained_columns', []):
            return fk.get('name')
    return None


def upgrade() -> None:
    """Upgrade schema: make user_stores.store_id FK ON DELETE CASCADE"""
    conn = op.get_bind()
    inspector = inspect(conn)

    fk_name = None
    try:
        fk_name = _find_fk_name_on_stores(inspector)
    except Exception:
        # If inspector fails (e.g., empty DB), continue and attempt to create FK
        fk_name = None

    # Use batch_alter_table for SQLite compatibility
    with op.batch_alter_table('user_stores') as batch_op:
        if fk_name:
            batch_op.drop_constraint(fk_name, type_='foreignkey')
        # Create a named FK with ON DELETE CASCADE
        batch_op.create_foreign_key(
            'fk_user_stores_store_id_stores',
            'stores',
            ['store_id'],
            ['id'],
            ondelete='CASCADE'
        )


def downgrade() -> None:
    """Downgrade: remove ON DELETE CASCADE from user_stores.store_id FK"""
    conn = op.get_bind()
    inspector = inspect(conn)

    fk_name = None
    try:
        fk_name = _find_fk_name_on_stores(inspector)
    except Exception:
        fk_name = None

    with op.batch_alter_table('user_stores') as batch_op:
        if fk_name:
            batch_op.drop_constraint(fk_name, type_='foreignkey')
        # Recreate FK without ON DELETE CASCADE
        batch_op.create_foreign_key(
            'fk_user_stores_store_id_stores',
            'stores',
            ['store_id'],
            ['id']
        )
