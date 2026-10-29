"""Minimal consented research events; no URL, body, IP or device fingerprint."""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "research_events",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("owner_hash", sa.String(64), nullable=False),
        sa.Column("verdict", sa.String(20), nullable=False),
        sa.Column("model_version", sa.String(100), nullable=False),
        sa.Column("source_status", sa.String(30), nullable=False),
        sa.Column("observed_hour", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index("ix_research_events_owner_hash", "research_events", ["owner_hash"])
    op.create_index("ix_research_events_expires_at", "research_events", ["expires_at"])


def downgrade():
    op.drop_table("research_events")
