"""Add missing tables: store_settings, user_settings, system_settings, analytics_events

Revision ID: f8baf3677160
Revises: e4a593920909
Create Date: 2025-12-31 08:14:48.703764

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f8baf3677160'
down_revision: Union[str, Sequence[str], None] = 'e4a593920909'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Use batch_alter_table for SQLite compatibility when altering columns.
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        # SQLite cannot ALTER COLUMN easily; use batch_alter_table to recreate the table safely.
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('server_seq', existing_type=sa.BIGINT(), type_=sa.Integer(), existing_nullable=False)
    else:
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.BIGINT(),
                   type_=sa.Integer(),
                   existing_nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    # Use batch_alter_table for SQLite compatibility when altering columns.
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        # SQLite cannot ALTER COLUMN easily; use batch_alter_table to recreate the table safely.
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('server_seq', existing_type=sa.Integer(), type_=sa.BIGINT(), existing_nullable=False)
    else:
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.Integer(),
                   type_=sa.BIGINT(),
                   existing_nullable=False)
