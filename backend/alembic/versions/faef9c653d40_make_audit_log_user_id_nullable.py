"""make_audit_log_user_id_nullable

Revision ID: faef9c653d40
Revises: 4928467ed0bf
Create Date: 2025-12-21 17:56:18.311660

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'faef9c653d40'
down_revision: Union[str, Sequence[str], None] = '4928467ed0bf'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Make user_id column nullable in audit_logs table
    with op.batch_alter_table('audit_logs') as batch_op:
        batch_op.alter_column('user_id', nullable=True)


def downgrade() -> None:
    """Downgrade schema."""
    # Make user_id column not nullable again (this will fail if there are NULL values)
    with op.batch_alter_table('audit_logs') as batch_op:
        batch_op.alter_column('user_id', nullable=False)
