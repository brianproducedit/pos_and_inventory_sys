"""Add changes table for sync

Revision ID: e5f1d2c3b4a6
Revises: mrg0001
Create Date: 2025-12-30 00:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e5f1d2c3b4a6'
down_revision: Union[str, Sequence[str], None] = 'mrg0001'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema: create changes table and add a trigger to set server_seq from id.

    Note: SQLite does not support sequences; we use a trigger to set `server_seq` to the inserted
    row's `id` (which is monotonic). For PostgreSQL we add a BEFORE INSERT trigger that copies `id`
    into `server_seq`.
    """
    # If the table already exists (e.g., running migrations twice against the same DB),
    # skip creating it again to be idempotent.
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if 'changes' in inspector.get_table_names():
        # Table already exists; safe to return early
        return

    # Create the changes table without a DB-specific sequence to remain compatible with SQLite
    op.create_table(
        'changes',
        sa.Column('id', sa.Integer(), primary_key=True, nullable=False),
        sa.Column('server_seq', sa.BigInteger(), nullable=True),
        sa.Column('entity_type', sa.String(length=64), nullable=False),
        sa.Column('entity_id', sa.String(length=128), nullable=True),
        sa.Column('operation', sa.String(length=16), nullable=False),
        sa.Column('payload', sa.JSON(), nullable=True),
        sa.Column('client_temp_id', sa.String(length=128), nullable=True),
        sa.Column('origin_client_id', sa.String(length=128), nullable=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
    )

    op.create_index('ix_changes_server_seq', 'changes', ['server_seq'])
    op.create_index('ix_changes_entity', 'changes', ['entity_type', 'entity_id'])

    # Add a trigger that sets server_seq to the row's id on insert. This keeps server_seq monotonic
    # and works across SQLite (and PostgreSQL with a small trigger function).
    dialect = bind.dialect.name
    if dialect == 'sqlite':
        op.execute("""
        CREATE TRIGGER set_changes_server_seq
        AFTER INSERT ON changes
        BEGIN
            UPDATE changes SET server_seq = NEW.id WHERE id = NEW.id;
        END;
        """)
    elif dialect == 'postgresql':
        op.execute("""
        CREATE FUNCTION set_changes_server_seq() RETURNS trigger AS $$
        BEGIN
            NEW.server_seq := NEW.id;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        CREATE TRIGGER set_changes_server_seq
        BEFORE INSERT ON changes
        FOR EACH ROW
        EXECUTE PROCEDURE set_changes_server_seq();
        """)

def downgrade() -> None:
    """Downgrade schema: drop changes table and any triggers created to set `server_seq`."""
    bind = op.get_bind()
    dialect = bind.dialect.name
    if dialect == 'sqlite':
        op.execute("DROP TRIGGER IF EXISTS set_changes_server_seq;")
    elif dialect == 'postgresql':
        op.execute("DROP TRIGGER IF EXISTS set_changes_server_seq ON changes;")
        op.execute("DROP FUNCTION IF EXISTS set_changes_server_seq();")

    op.drop_index('ix_changes_entity', table_name='changes')
    op.drop_index('ix_changes_server_seq', table_name='changes')
    op.drop_table('changes')