from datetime import datetime, timedelta, timezone

import pytest

from lynveris.combined_sources import CombinedSources
from lynveris.schemas import ThreatResult


class SourceFixture:
    def __init__(self, name, status):
        self.SOURCE, self.status = name, status
        self.cleared = False

    async def check(self, url):
        now = datetime.now(timezone.utc)
        return ThreatResult(
            source=self.SOURCE,
            status=self.status,
            checked_at=now,
            expires_at=now + timedelta(minutes=1)
            if self.status in {"detected", "not_found"}
            else None,
            attribution="Advisory provided by Google"
            if self.SOURCE == "Google Safe Browsing" and self.status == "detected"
            else None,
        )

    def clear_cache(self):
        self.cleared = True


@pytest.mark.asyncio
async def test_fallback_detection_does_not_get_google_attribution():
    source = CombinedSources(
        SourceFixture("Google Safe Browsing", "timeout"),
        SourceFixture("OpenPhish Community", "detected"),
    )
    result = await source.check("https://example.org")
    assert result.status == "detected" and result.source == "OpenPhish Community"
    assert result.attribution is None and result.partial
    assert len(result.checks) == 2


@pytest.mark.asyncio
async def test_partial_negative_remains_incomplete_and_caches_clear_together():
    google, feed = (
        SourceFixture("Google Safe Browsing", "not_configured"),
        SourceFixture("OpenPhish Community", "not_found"),
    )
    source = CombinedSources(google, feed)
    result = await source.check("https://example.org")
    assert result.status == "not_configured" and result.partial
    source.clear_cache()
    assert google.cleared and feed.cleared


@pytest.mark.asyncio
async def test_both_sources_checked_and_primary_google_attribution_preserved():
    source = CombinedSources(
        SourceFixture("Google Safe Browsing", "detected"),
        SourceFixture("OpenPhish Community", "detected"),
    )
    result = await source.check("https://example.org")
    assert (
        result.source == "Google Safe Browsing"
        and result.attribution == "Advisory provided by Google"
    )
    assert not result.partial and len(result.checks) == 2


@pytest.mark.asyncio
async def test_expired_hit_and_exception_do_not_create_a_warning_or_complete_negative():
    class Expired(SourceFixture):
        async def check(self, url):
            result = await super().check(url)
            result.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
            return result

    class Broken(SourceFixture):
        async def check(self, url):
            raise RuntimeError("private URL token must not escape")

    result = await CombinedSources(
        Expired("Google Safe Browsing", "detected"), Broken("OpenPhish Community", "error")
    ).check("https://example.org/")
    assert result.status == "error" and result.partial
    assert result.attribution is None
    assert "private URL token" not in result.model_dump_json()


@pytest.mark.asyncio
async def test_sources_start_concurrently():
    import asyncio

    started = set()
    both = asyncio.Event()

    class Concurrent(SourceFixture):
        async def check(self, url):
            started.add(self.SOURCE)
            if len(started) == 2:
                both.set()
            await asyncio.wait_for(both.wait(), timeout=1)
            return await super().check(url)

    result = await CombinedSources(
        Concurrent("Google Safe Browsing", "not_found"),
        Concurrent("OpenPhish Community", "not_found"),
    ).check("https://example.org/")
    assert result.status == "not_found" and not result.partial
