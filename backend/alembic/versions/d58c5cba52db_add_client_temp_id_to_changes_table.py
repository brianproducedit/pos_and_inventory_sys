"""add_client_temp_id_to_changes_table

Revision ID: d58c5cba52db
Revises: f8baf3677160
Create Date: 2025-12-31 10:32:57.491268

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'd58c5cba52db'
down_revision: Union[str, Sequence[str], None] = 'f8baf3677160'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema: add client_temp_id column to changes table (idempotent)."""
    # Check if column already exists (it's created in e5f1d2c3b4a6)
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    columns = [col['name'] for col in inspector.get_columns('changes')]
    if 'client_temp_id' not in columns:
        op.add_column('changes', sa.Column('client_temp_id', sa.String(length=128), nullable=True))


def downgrade() -> None:
    """Downgrade schema: remove client_temp_id column from changes table."""
    op.drop_column('changes', 'client_temp_id')
