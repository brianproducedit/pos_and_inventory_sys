"""Merge heads

Revision ID: cf9e0fa683de
Revises: a9d8c7b6e5f4, d58c5cba52db
Create Date: 2026-01-05 14:01:30.641257

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'cf9e0fa683de'
down_revision: Union[str, Sequence[str], None] = ('a9d8c7b6e5f4', 'd58c5cba52db')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
