"""add transaction_number to sales

Revision ID: a9d8c7b6e5f4
Revises: mrg0001
Create Date: 2026-01-05 09:50:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = 'a9d8c7b6e5f4'
down_revision = 'mrg0001'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Add column as nullable first
    op.add_column('sales', sa.Column('transaction_number', sa.String(), nullable=True))

    # Backfill existing rows with a stable value using the primary key
    # Use server-side concatenation to produce 'sales#<id>' per row
    op.execute("""
    UPDATE sales
    SET transaction_number = 'sales#' || id::text
    WHERE transaction_number IS NULL;
    """)

    # Make the column NOT NULL now that we've backfilled
    op.alter_column('sales', 'transaction_number', nullable=False)

    # Create index on transaction_number for fast lookups
    op.create_index('idx_sales_transaction_number', 'sales', ['transaction_number'], unique=False)


def downgrade() -> None:
    # Drop index and column
    op.drop_index('idx_sales_transaction_number', table_name='sales')
    op.drop_column('sales', 'transaction_number')
