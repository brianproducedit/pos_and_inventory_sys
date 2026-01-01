"""Add is_active and full_name fields to User and Store models

Revision ID: 3bc044bbacc8
Revises: 633d43e0ccd4
Create Date: 2025-12-20 06:58:55.578337

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '3bc044bbacc8'
down_revision: Union[str, Sequence[str], None] = '633d43e0ccd4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # is_active already exists in stores table, just add to users table
    op.add_column('users', sa.Column('is_active', sa.Boolean(), nullable=True, default=True))
    op.add_column('users', sa.Column('full_name', sa.String(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    # Remove columns from users table only
    op.drop_column('users', 'full_name')
    op.drop_column('users', 'is_active')
    # Note: is_active in stores table is not removed as it was added separately


def downgrade() -> None:
    """Downgrade schema."""
    # Remove columns in reverse order
    op.drop_column('users', 'full_name')
    op.drop_column('users', 'is_active')
    op.drop_column('stores', 'is_active')
