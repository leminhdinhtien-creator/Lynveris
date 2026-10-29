from fastapi.testclient import TestClient

from lynveris.api import create_app
from lynveris.config import Settings


def client(tmp_path, **kwargs):
    return TestClient(
        create_app(
            Settings(
                _env_file=None,
                database_url=f"sqlite:///{tmp_path}/test.db",
                rate_limit_per_minute=3,
                **kwargs,
            )
        )
    )


def test_end_to_end_and_no_fake_model(tmp_path):
    with client(tmp_path) as c:
        r = c.post("/v1/check", json={"url": "https://аррӏе.com/login"})
        assert r.status_code == 200
        body = r.json()
        assert body["verdict"] == "caution" and body["model"]["status"] == "unavailable"
        assert body["threat"]["status"] == "skipped"
        assert "probability" not in body
        assert body["redirect"]["status"] == "not_requested"


def test_missing_evidence_never_returns_clear(tmp_path):
    with client(tmp_path) as c:
        assert (
            c.post("/v1/check", json={"url": "https://example.org"}).json()["verdict"]
            == "insufficient"
        )


def test_accidental_message_field_is_rejected(tmp_path):
    with client(tmp_path) as c:
        result = c.post("/v1/check", json={"url": "https://example.org", "message": "private text"})
        assert result.status_code == 422
        assert "private text" not in result.text


def test_invalid_size_and_rate_limit(tmp_path):
    with client(tmp_path) as c:
        assert c.post("/v1/check", json={"url": "file:///secret"}).status_code == 422
        assert c.post("/v1/check", content=b"x" * 20000).status_code == 413
        assert c.post("/v1/check", json={"url": "https://example.com"}).status_code == 200
        assert c.post("/v1/check", json={"url": "https://example.com"}).status_code == 200
        assert c.post("/v1/check", json={"url": "https://example.com"}).status_code == 429


def test_opt_in_delete_and_no_raw_urls(tmp_path):
    token = "a" * 40
    with client(tmp_path) as c:
        c.post(
            "/v1/check",
            json={
                "url": "https://example.com?token=supersecret",
                "research_consent": True,
                "deletion_token": token,
            },
        )
        from sqlalchemy import text

        with c.app.state.engine.connect() as db:
            rows = db.execute(text("select * from research_events")).fetchall()
            assert len(rows) == 1 and "supersecret" not in str(rows) and token not in str(rows)
        assert c.delete("/v1/research", headers={"X-Deletion-Token": token}).json()["deleted"] == 1


def test_no_url_fetch_even_for_internal_destination(tmp_path):
    with client(tmp_path) as c:
        r = c.post("/v1/check", json={"url": "http://169.254.169.254/latest/meta-data/"})
        assert r.status_code == 200
        assert r.json()["redirect"]["status"] == "not_requested"
        assert "non_public_address" in [s["code"] for s in r.json()["signals"]]


def test_preservation_mode_keeps_preexisting_expired_rows(tmp_path):
    from datetime import datetime, timedelta, timezone

    from sqlalchemy import select

    from lynveris.database import Base, ResearchEvent, engine_for

    url = f"sqlite:///{tmp_path}/existing.db"
    engine = engine_for(url)
    Base.metadata.create_all(engine)
    with engine.begin() as db:
        db.execute(
            ResearchEvent.__table__.insert().values(
                id="preexisting",
                owner_hash="other-owner",
                verdict="insufficient",
                model_version="unavailable",
                source_status="skipped",
                observed_hour=datetime.now(timezone.utc) - timedelta(days=10),
                expires_at=datetime.now(timezone.utc) - timedelta(days=3),
            )
        )
    with TestClient(
        create_app(Settings(_env_file=None, database_url=url, retention_cleanup_enabled=False))
    ) as c:
        response = c.post(
            "/v1/check",
            json={
                "url": "https://example.org",
                "research_consent": True,
                "deletion_token": "preservation-check-" + "x" * 32,
            },
        )
        assert response.status_code == 200
        assert (
            c.delete(
                "/v1/research",
                headers={
                    "X-Deletion-Token": "preservation-check-" + "x" * 32,
                },
            ).json()["deleted"]
            == 1
        )
    with engine.connect() as db:
        assert db.execute(select(ResearchEvent.id)).scalars().all() == ["preexisting"]
    engine.dispose()
