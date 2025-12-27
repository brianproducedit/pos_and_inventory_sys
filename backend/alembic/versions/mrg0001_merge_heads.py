"""merge_heads

Revision ID: mrg0001
Revises: b617a2c9d3f1, c2b7f4d6e59a
Create Date: 2025-12-27 00:00:00.000000

"""
from alembic import op
from typing import Sequence, Union

# revision identifiers, used by Alembic.
revision = 'mrg0001'
down_revision = ('b617a2c9d3f1', 'c2b7f4d6e59a')
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Merge migration — marks multiple heads as a single head. No DB changes."""
    pass


def downgrade() -> None:
    """Downgrade — noop for merge migration."""
    pass
