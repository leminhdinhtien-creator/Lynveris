"""Negative security cases for the W07 freeze; no external URL is fetched."""

import secrets

from fastapi.testclient import TestClient
from sqlalchemy import select

from lynveris.api import create_app
from lynveris.config import Settings
from lynveris.database import ResearchEvent


def app_for(tmp_path, limit=30):
    return create_app(
        Settings(
            _env_file=None,
            database_url=f"sqlite:///{tmp_path}/security.db",
            model_directory="",
            google_api_key="",
            rate_limit_per_minute=limit,
        )
    )


def test_guard_rejections_are_never_cacheable(tmp_path):
    with TestClient(app_for(tmp_path, limit=1)) as client:
        huge = client.post("/v1/check", content=b"x" * 16385)
        assert huge.status_code == 413
        assert huge.headers["cache-control"] == "no-store"
        assert client.post("/v1/check", json={"url": "https://example.org"}).status_code == 200
        limited = client.post("/v1/check", json={"url": "https://example.org"})
        assert limited.status_code == 429
        assert limited.headers["retry-after"] == "60"
        assert limited.headers["cache-control"] == "no-store"


def test_a_different_owner_and_sql_text_cannot_delete_our_event(tmp_path):
    owner = secrets.token_hex(32)
    with TestClient(app_for(tmp_path)) as client:
        result = client.post(
            "/v1/check",
            json={
                "url": "https://example.org/?token=private-marker",
                "research_consent": True,
                "deletion_token": owner,
            },
        )
        assert result.status_code == 200
        event_id = result.json()["id"]
        assert client.delete("/v1/research").status_code == 422
        for other in (secrets.token_hex(32), "' OR '1'='1' --" + "x" * 32):
            response = client.delete("/v1/research", headers={"X-Deletion-Token": other})
            assert response.json() == {"deleted": 0}
        with client.app.state.engine.connect() as db:
            row = db.execute(select(ResearchEvent.__table__)).mappings().one()
            assert row["id"] == event_id
            assert owner not in str(row) and "private-marker" not in str(row)
        assert client.delete("/v1/research", headers={"X-Deletion-Token": owner}).json() == {
            "deleted": 1
        }


def test_forwarded_headers_do_not_bypass_the_client_limit(tmp_path):
    with TestClient(app_for(tmp_path, limit=1)) as client:
        for index, expected in enumerate((200, 429)):
            response = client.post(
                "/v1/check",
                json={"url": "https://example.org"},
                headers={"X-Forwarded-For": f"203.0.113.{index + 1}"},
            )
            assert response.status_code == expected
        assert client.get("/health").status_code == 200


def test_unapproved_web_origin_and_reflected_input_are_blocked(tmp_path):
    with TestClient(app_for(tmp_path)) as client:
        preflight = client.options(
            "/v1/check",
            headers={
                "Origin": "https://unapproved.example",
                "Access-Control-Request-Method": "POST",
            },
        )
        assert preflight.status_code == 400
        assert "access-control-allow-origin" not in preflight.headers
        response = client.post(
            "/v1/check",
            json={"url": "javascript:alert('private-marker')", "message": "private-marker"},
        )
        assert response.status_code == 422
        assert "private-marker" not in response.text
