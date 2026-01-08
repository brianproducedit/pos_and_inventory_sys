"""Add sku field to products table

Revision ID: b1891f56b4aa
Revises: cf9e0fa683de
Create Date: 2026-01-05 14:01:41.875428

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b1891f56b4aa'
down_revision: Union[str, Sequence[str], None] = 'cf9e0fa683de'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.add_column('products', sa.Column('sku', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('products', 'sku')
