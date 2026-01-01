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
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    existing_tables = inspector.get_table_names()
    
    # Create store_settings table if it doesn't exist
    if 'store_settings' not in existing_tables:
        op.create_table('store_settings',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('store_id', sa.Integer(), nullable=False),
            sa.Column('business_name', sa.String(), nullable=True),
            sa.Column('address', sa.Text(), nullable=True),
            sa.Column('phone', sa.String(), nullable=True),
            sa.Column('email', sa.String(), nullable=True),
            sa.Column('tax_number', sa.String(), nullable=True),
            sa.Column('receipt_footer', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=True),
            sa.Column('updated_at', sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(['store_id'], ['stores.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index(op.f('ix_store_settings_id'), 'store_settings', ['id'], unique=False)
    
    # Create user_settings table if it doesn't exist
    if 'user_settings' not in existing_tables:
        op.create_table('user_settings',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=False),
            sa.Column('theme', sa.String(), nullable=True),
            sa.Column('language', sa.String(), nullable=True),
            sa.Column('notifications_enabled', sa.Boolean(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=True),
            sa.Column('updated_at', sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index(op.f('ix_user_settings_id'), 'user_settings', ['id'], unique=False)
    
    # Create system_settings table if it doesn't exist
    if 'system_settings' not in existing_tables:
        op.create_table('system_settings',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('key', sa.String(), nullable=False),
            sa.Column('value', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=True),
            sa.Column('updated_at', sa.DateTime(), nullable=True),
            sa.PrimaryKeyConstraint('id'),
            sa.UniqueConstraint('key')
        )
        op.create_index(op.f('ix_system_settings_id'), 'system_settings', ['id'], unique=False)
    
    # Create analytics_events table if it doesn't exist
    if 'analytics_events' not in existing_tables:
        op.create_table('analytics_events',
            sa.Column('id', sa.Integer(), nullable=False),
            sa.Column('event_name', sa.String(), nullable=False),
            sa.Column('user_id', sa.Integer(), nullable=True),
            sa.Column('from_store_id', sa.Integer(), nullable=True),
            sa.Column('to_store_id', sa.Integer(), nullable=True),
            sa.Column('duration_ms', sa.Integer(), nullable=True),
            sa.Column('metadata_json', sa.Text(), nullable=True),
            sa.Column('ip_address', sa.String(), nullable=True),
            sa.Column('user_agent', sa.String(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=True),
            sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
            sa.ForeignKeyConstraint(['from_store_id'], ['stores.id'], ),
            sa.ForeignKeyConstraint(['to_store_id'], ['stores.id'], ),
            sa.PrimaryKeyConstraint('id')
        )
        op.create_index(op.f('ix_analytics_events_id'), 'analytics_events', ['id'], unique=False)
    
    # Alter changes.server_seq column type
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('server_seq', existing_type=sa.BIGINT(), type_=sa.Integer(), existing_nullable=False)
    else:
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.BIGINT(),
                   type_=sa.Integer(),
                   existing_nullable=False)


def downgrade() -> None:
    """Downgrade schema."""
    # Drop tables in reverse order
    op.drop_index(op.f('ix_analytics_events_id'), table_name='analytics_events')
    op.drop_table('analytics_events')
    
    op.drop_index(op.f('ix_system_settings_id'), table_name='system_settings')
    op.drop_table('system_settings')
    
    op.drop_index(op.f('ix_user_settings_id'), table_name='user_settings')
    op.drop_table('user_settings')
    
    op.drop_index(op.f('ix_store_settings_id'), table_name='store_settings')
    op.drop_table('store_settings')
    
    # Revert changes.server_seq column type
    bind = op.get_bind()
    if bind.dialect.name == 'sqlite':
        with op.batch_alter_table('changes') as batch_op:
            batch_op.alter_column('server_seq', existing_type=sa.Integer(), type_=sa.BIGINT(), existing_nullable=False)
    else:
        op.alter_column('changes', 'server_seq',
                   existing_type=sa.Integer(),
                   type_=sa.BIGINT(),
                   existing_nullable=False)
