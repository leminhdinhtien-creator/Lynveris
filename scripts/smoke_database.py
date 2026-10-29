"""Runs against the selected real migrated database; no provider mock and no external lookup."""

import secrets

from fastapi.testclient import TestClient
from lynveris.api import create_app
from lynveris.config import Settings
from lynveris.database import ResearchEvent, owner_hash
from sqlalchemy import select

token = secrets.token_urlsafe(40)

with TestClient(create_app(Settings(retention_cleanup_enabled=False))) as client:
    with client.app.state.engine.connect() as db:
        before = set(db.execute(select(ResearchEvent.id)).scalars())
    assert client.get("/ready").status_code == 200
    result = client.post(
        "/v1/check",
        json={
            "url": "https://example.org/",
            "research_consent": True,
            "deletion_token": token,
        },
    )
    assert result.status_code == 200
    with client.app.state.engine.connect() as db:
        row = (
            db.execute(
                select(ResearchEvent.__table__).where(ResearchEvent.id == result.json()["id"])
            )
            .mappings()
            .one()
        )
        assert row["owner_hash"] == owner_hash(token)
        assert row["source_status"] == "skipped"
    erased = client.delete("/v1/research", headers={"X-Deletion-Token": token})
    assert erased.status_code == 200 and erased.json()["deleted"] == 1
    with client.app.state.engine.connect() as db:
        assert set(db.execute(select(ResearchEvent.id)).scalars()) == before
print(
    "Real database: readiness, consented insert, SQL read and exact-owner deletion passed; existing row IDs unchanged."
)
