"""Academic/personal Community feed lookup. No submitted URL leaves the backend.

Source terms: https://openphish.com/terms.html . No feed redistribution.
Feed receipt time is not a URL submission/verification time or a training label time.
"""

import asyncio
import hashlib
import time
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime

import httpx

from .schemas import ThreatResult
from .urls import UrlError, parse_url


class OpenPhishCommunity:
    ENDPOINT = "https://raw.githubusercontent.com/openphish/public_feed/refs/heads/main/feed.txt"
    SOURCE = "OpenPhish Community"

    def __init__(self, enabled=False, *, transport=None):
        self.enabled = enabled
        self.transport = transport  # Test transport only; production always uses HTTPS.
        self.hashes = set()
        self.received_at = self.expires_at = None
        self.retry_at = 0.0
        self.last_failure = "error"
        self.lock = asyncio.Lock()

    def clear_cache(self):
        self.hashes = set()
        self.received_at = self.expires_at = None

    async def _refresh(self):
        # Fixed destination, no redirect following, bounded decompressed bytes and URLs.
        async with httpx.AsyncClient(
            transport=self.transport, timeout=3, follow_redirects=False, trust_env=False
        ) as client:
            for attempt in range(2):
                try:
                    async with client.stream(
                        "GET", self.ENDPOINT, headers={"User-Agent": "Lynveris-academic/0.1"}
                    ) as response:
                        if response.status_code == 429:
                            return "quota"
                        if response.status_code >= 500 and attempt == 0:
                            await asyncio.sleep(0.1)
                            continue
                        response.raise_for_status()
                        received = datetime.now(timezone.utc)
                        if response.headers.get("Last-Modified"):
                            modified = parsedate_to_datetime(response.headers["Last-Modified"])
                            if modified.tzinfo is None or not received - timedelta(
                                hours=24
                            ) <= modified <= received + timedelta(minutes=5):
                                return "error"
                        body = bytearray()
                        async for chunk in response.aiter_bytes():
                            body.extend(chunk)
                            if len(body) > 2 * 1024 * 1024:
                                return "error"
                        lines = bytes(body).decode("utf-8").splitlines()
                        if not 1 <= len(lines) <= 10000:
                            return "error"
                        hashes, invalid = set(), 0
                        for line in lines:
                            try:
                                canonical = parse_url(line.strip()).fetch_url
                            except UrlError:
                                invalid += 1
                                continue
                            hashes.add(hashlib.sha256(canonical.encode()).digest())
                        if not hashes or invalid > max(1, len(lines) // 10):
                            return "error"
                        self.hashes = hashes
                        self.received_at = received
                        self.expires_at = received + timedelta(hours=1)
                        return None
                except httpx.TimeoutException:
                    if attempt == 1:
                        return "timeout"
                except (httpx.HTTPError, ValueError, TypeError, OverflowError, UnicodeError):
                    return "error"
        return "error"

    async def check(self, url):
        if not self.enabled:
            return ThreatResult(source=self.SOURCE, status="not_configured")
        cached = True
        async with self.lock:
            if self.expires_at is None or self.expires_at <= datetime.now(timezone.utc):
                if time.monotonic() < self.retry_at:
                    return ThreatResult(
                        source=self.SOURCE,
                        status=self.last_failure,
                        checked_at=datetime.now(timezone.utc),
                    )
                try:
                    failure = await asyncio.wait_for(self._refresh(), timeout=8)
                except asyncio.TimeoutError:
                    failure = "timeout"
                if failure:
                    self.retry_at = time.monotonic() + 60
                    self.last_failure = failure
                    return ThreatResult(
                        source=self.SOURCE, status=failure, checked_at=datetime.now(timezone.utc)
                    )
                cached = False
            # Snapshot references before a deletion request can invalidate the shared cache.
            hashes, expires_at, received_at = self.hashes, self.expires_at, self.received_at
        match = hashlib.sha256(url.encode()).digest() in hashes
        return ThreatResult(
            source=self.SOURCE,
            status="detected" if match else "not_found",
            checked_at=datetime.now(timezone.utc),
            expires_at=expires_at,
            feed_received_at=received_at,
            cached=cached,
            categories=["PHISHING"] if match else [],
            attribution="OpenPhish Community (academic/personal research)" if match else None,
            advisory_url="https://openphish.com/phishing_feeds.html" if match else None,
        )
