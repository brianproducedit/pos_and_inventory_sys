"""add_must_change_password_to_users

Revision ID: b617a2c9d3f1
Revises: faef9c653d40
Create Date: 2025-12-27 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'b617a2c9d3f1'
down_revision = 'faef9c653d40'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add must_change_password column to users table."""
    with op.batch_alter_table('users') as batch_op:
        batch_op.add_column(sa.Column('must_change_password', sa.Boolean(), nullable=False, server_default=sa.false()))

    # Ensure existing superadmin (if username 'superadmin') is set to force password change
    op.execute("UPDATE users SET must_change_password = true WHERE username = 'superadmin'")


def downgrade() -> None:
    """Remove must_change_password column."""
    with op.batch_alter_table('users') as batch_op:
        batch_op.drop_column('must_change_password')
