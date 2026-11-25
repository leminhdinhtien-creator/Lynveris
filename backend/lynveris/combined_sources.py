"""Combine independent live sources without hiding incomplete lookups."""

import asyncio
from datetime import datetime, timezone

from .schemas import ThreatResult


class CombinedSources:
    SOURCE = "Google Safe Browsing + OpenPhish Community"

    def __init__(self, *sources):
        if not sources:
            raise ValueError("At least one source is required")
        self.sources = sources

    def clear_cache(self):
        for source in self.sources:
            source.clear_cache()

    async def _check(self, source, url):
        try:
            result = await asyncio.wait_for(source.check(url), timeout=9)
            if result.status in {"detected", "not_found"} and (
                result.expires_at is None or result.expires_at <= datetime.now(timezone.utc)
            ):
                raise ValueError("Expired source result")
            return result
        except asyncio.TimeoutError:
            status = "timeout"
        except Exception:
            # Never expose exception text: provider requests may contain URL tokens or keys.
            status = "error"
        return ThreatResult(
            source=source.SOURCE, status=status, checked_at=datetime.now(timezone.utc)
        )

    async def check(self, url):
        checks = list(await asyncio.gather(*(self._check(s, url) for s in self.sources)))
        failures = [c for c in checks if c.status not in {"detected", "not_found"}]
        hits = [c for c in checks if c.status == "detected"]
        if hits:
            # Attribute Google's advisory only when Google actually returned a hit.
            primary = next((c for c in hits if c.source == "Google Safe Browsing"), hits[0])
            return primary.model_copy(update={"partial": bool(failures), "checks": checks})
        if failures:
            return ThreatResult(
                source=self.SOURCE,
                status=failures[0].status,
                checked_at=datetime.now(timezone.utc),
                partial=True,
                checks=checks,
            )
        return ThreatResult(
            source=self.SOURCE,
            status="not_found",
            checked_at=datetime.now(timezone.utc),
            expires_at=min(c.expires_at for c in checks),
            cached=all(c.cached for c in checks),
            checks=checks,
        )
