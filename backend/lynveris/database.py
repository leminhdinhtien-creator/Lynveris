import hashlib
from datetime import datetime, timedelta, timezone

from sqlalchemy import Column, DateTime, String, create_engine, delete
from sqlalchemy.orm import declarative_base

Base = declarative_base()


class ResearchEvent(Base):
    __tablename__ = "research_events"
    id = Column(String(36), primary_key=True)
    owner_hash = Column(String(64), nullable=False, index=True)
    verdict = Column(String(20), nullable=False)
    model_version = Column(String(100), nullable=False)
    source_status = Column(String(30), nullable=False)
    observed_hour = Column(DateTime(timezone=True), nullable=False)
    expires_at = Column(DateTime(timezone=True), nullable=False, index=True)


def engine_for(url):
    return create_engine(
        url,
        pool_pre_ping=True,
        connect_args={"check_same_thread": False} if url.startswith("sqlite") else {},
    )


def owner_hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def cleanup(engine):
    with engine.begin() as db:
        db.execute(
            delete(ResearchEvent).where(ResearchEvent.expires_at < datetime.now(timezone.utc))
        )


def record_event(engine, result, token):
    cleanup(engine)
    with engine.begin() as db:
        db.execute(
            ResearchEvent.__table__.insert().values(
                id=result.id,
                owner_hash=owner_hash(token),
                verdict=result.verdict,
                model_version=result.model.version or "unavailable",
                source_status=result.threat.status,
                observed_hour=result.checked_at.replace(minute=0, second=0, microsecond=0),
                expires_at=result.checked_at + timedelta(days=7),
            )
        )


def delete_events(engine, token):
    with engine.begin() as db:
        return db.execute(
            delete(ResearchEvent).where(ResearchEvent.owner_hash == owner_hash(token))
        ).rowcount
