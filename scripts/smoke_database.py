"""Runs against the selected real migrated database; no provider mock and no external lookup."""

from fastapi.testclient import TestClient
from lynveris.api import create_app

with TestClient(create_app()) as client:
    assert client.get("/ready").status_code == 200
    result = client.post(
        "/v1/check",
        json={
            "url": "https://example.org/",
            "research_consent": True,
            "deletion_token": "integration-check-" + "x" * 32,
        },
    )
    assert result.status_code == 200
    assert result.json()["verdict"] == "insufficient"
    erased = client.delete(
        "/v1/research", headers={"X-Deletion-Token": "integration-check-" + "x" * 32}
    )
    assert erased.status_code == 200 and erased.json()["deleted"] == 1
print("Real database: readiness, check, consented insert and deletion passed.")
