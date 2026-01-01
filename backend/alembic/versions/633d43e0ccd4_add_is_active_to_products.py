"""add_is_active_to_products

Revision ID: 633d43e0ccd4
Revises: 1b6d08654485
Create Date: 2025-12-20 05:45:06.740445

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '633d43e0ccd4'
down_revision: Union[str, Sequence[str], None] = '1b6d08654485'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add is_active column to products table
    op.add_column('products', sa.Column('is_active', sa.Boolean(), nullable=True, default=True))

    # Set default value for existing records (use TRUE for PostgreSQL boolean)
    op.execute("UPDATE products SET is_active = TRUE WHERE is_active IS NULL")


def downgrade() -> None:
    """Downgrade schema."""
    # Remove is_active column from products table
    op.drop_column('products', 'is_active')
