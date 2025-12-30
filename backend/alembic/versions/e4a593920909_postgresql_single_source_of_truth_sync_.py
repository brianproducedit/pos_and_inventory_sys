"""PostgreSQL (single source of truth) + sync endpoints and a change-log table (append-only) or logical decoding stream

Revision ID: e4a593920909
Revises: e5f1d2c3b4a6
Create Date: 2025-12-30 14:17:52.671334

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'e4a593920909'
down_revision: Union[str, Sequence[str], None] = 'e5f1d2c3b4a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Use batch_alter_table for SQLite compatibility when altering columns.
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        # SQLite cannot ALTER COLUMN easily; use batch_alter_table to recreate the table safely.
        # Ensure a previous failed tmp table is removed to avoid conflicts
        try:
            op.execute("DROP TABLE IF EXISTS _alembic_tmp_changes;")
        except Exception:
            pass
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('server_seq', existing_type=sa.Integer(), nullable=False)
            batch_op.alter_column('created_at', existing_type=sa.DATETIME(), nullable=True, existing_server_default=sa.text('(now())'))
        # Recreate indexes as needed (guarded to avoid aborting the transaction if missing)
        inspector = sa.inspect(bind)
        existing_indexes = {idx['name'] for idx in inspector.get_indexes('changes')}
        name_entity = op.f('ix_changes_entity')
        name_server_seq = op.f('ix_changes_server_seq')
        name_id = op.f('ix_changes_id')
        if name_entity in existing_indexes:
            op.drop_index(name_entity, table_name='changes')
        if name_server_seq in existing_indexes:
            op.drop_index(name_server_seq, table_name='changes')
        if name_server_seq not in existing_indexes:
            op.create_index(name_server_seq, 'changes', ['server_seq'], unique=True)
        if name_id not in existing_indexes:
            op.create_index(name_id, 'changes', ['id'], unique=False)
    else:
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.BIGINT(),
                   type_=sa.Integer(),
                   nullable=False)
        op.alter_column('changes', 'created_at',
                   existing_type=sa.DATETIME(),
                   nullable=True,
                   existing_server_default=sa.text('(now())'))
        inspector = sa.inspect(bind)
        existing_indexes = {idx['name'] for idx in inspector.get_indexes('changes')}
        name_entity = op.f('ix_changes_entity')
        name_server_seq = op.f('ix_changes_server_seq')
        name_id = op.f('ix_changes_id')
        if name_entity in existing_indexes:
            op.drop_index(name_entity, table_name='changes')
        if name_server_seq in existing_indexes:
            op.drop_index(name_server_seq, table_name='changes')
        if name_server_seq not in existing_indexes:
            op.create_index(name_server_seq, 'changes', ['server_seq'], unique=True)
        if name_id not in existing_indexes:
            op.create_index(name_id, 'changes', ['id'], unique=False)

    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('user_stores') as batch_op:
            try:
                batch_op.drop_constraint(op.f('fk_user_stores_store_id_stores'), type_='foreignkey')
            except Exception:
                pass
            batch_op.create_foreign_key(op.f('fk_user_stores_store_id_stores'), 'stores', ['store_id'], ['id'])
    else:
        inspector = sa.inspect(bind)
        fk_names = {fk['name'] for fk in inspector.get_foreign_keys('user_stores')}
        fk_name = op.f('fk_user_stores_store_id_stores')
        if fk_name in fk_names:
            op.drop_constraint(fk_name, 'user_stores', type_='foreignkey')
        op.create_foreign_key(None, 'user_stores', 'stores', ['store_id'], ['id'])
    # Alter users.must_change_password in a cross-dialect way
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('users') as batch_op:
            batch_op.alter_column('must_change_password', existing_type=sa.BOOLEAN(), nullable=True, existing_server_default=sa.text('0'))
    else:
        op.alter_column('users', 'must_change_password',
                   existing_type=sa.BOOLEAN(),
                   nullable=True,
                   existing_server_default=sa.text('0'))
    # ### end Alembic commands ###


def downgrade() -> None:
    """Downgrade schema."""
    # Use batch_alter_table for SQLite compatibility when altering columns.
    bind = op.get_bind()
    # Alter users.must_change_password in a cross-dialect way
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('users') as batch_op:
            batch_op.alter_column('must_change_password', existing_type=sa.BOOLEAN(), nullable=False, existing_server_default=sa.text('0'))
    else:
        op.alter_column('users', 'must_change_password',
                   existing_type=sa.BOOLEAN(),
                   nullable=False,
                   existing_server_default=sa.text('0'))
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('user_stores') as batch_op:
            try:
                batch_op.drop_constraint(None, type_='foreignkey')
            except Exception:
                pass
            batch_op.create_foreign_key(op.f('fk_user_stores_store_id_stores'), 'stores', ['store_id'], ['id'], ondelete='CASCADE')
    else:
        op.drop_constraint(None, 'user_stores', type_='foreignkey')
        op.create_foreign_key(op.f('fk_user_stores_store_id_stores'), 'user_stores', 'stores', ['store_id'], ['id'], ondelete='CASCADE')

    if bind.dialect.name == 'sqlite':
        try:
            op.execute("DROP TABLE IF EXISTS _alembic_tmp_changes;")
        except Exception:
            pass
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('created_at', existing_type=sa.DATETIME(), nullable=False, existing_server_default=sa.text('(now())'))
            batch_op.alter_column('server_seq', existing_type=sa.Integer(), type_=sa.BIGINT(), nullable=True)
        try:
            op.drop_index(op.f('ix_changes_id'), table_name='changes')
        except Exception:
            pass
        try:
            op.drop_index(op.f('ix_changes_server_seq'), table_name='changes')
        except Exception:
            pass
        op.create_index(op.f('ix_changes_server_seq'), 'changes', ['server_seq'], unique=False)
        op.create_index(op.f('ix_changes_entity'), 'changes', ['entity_type', 'entity_id'], unique=False)
    else:
        inspector = sa.inspect(bind)
        existing_indexes = {idx['name'] for idx in inspector.get_indexes('changes')}
        name_id = op.f('ix_changes_id')
        name_server_seq = op.f('ix_changes_server_seq')
        name_entity = op.f('ix_changes_entity')
        if name_id in existing_indexes:
            op.drop_index(name_id, table_name='changes')
        if name_server_seq in existing_indexes:
            op.drop_index(name_server_seq, table_name='changes')
        if name_server_seq not in existing_indexes:
            op.create_index(name_server_seq, 'changes', ['server_seq'], unique=False)
        if name_entity not in existing_indexes:
            op.create_index(name_entity, 'changes', ['entity_type', 'entity_id'], unique=False)
        op.alter_column('changes', 'created_at',
                   existing_type=sa.DATETIME(),
                   nullable=False,
                   existing_server_default=sa.text('(now())'))
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.Integer(),
                   type_=sa.BIGINT(),
                   nullable=True)
    # ### end Alembic commands ###
