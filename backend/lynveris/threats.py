"""Live Google Lookup adapter. Never connects to the user-supplied URL."""

import asyncio
import hashlib
import hmac
import re
import secrets
from collections import OrderedDict
from datetime import datetime, timedelta, timezone
from typing import Protocol

import httpx

from .schemas import ThreatResult


def now():
    return datetime.now(timezone.utc)


class ThreatSource(Protocol):
    async def check(self, url: str) -> ThreatResult: ...


class GoogleSafeBrowsing:
    SOURCE = "Google Safe Browsing"
    ENDPOINT = "https://safebrowsing.googleapis.com/v4/threatMatches:find"

    def __init__(self, api_key: str, transport=None):
        self._key = api_key
        self._salt = secrets.token_bytes(32)
        self._transport = transport
        self.cache: OrderedDict[str, ThreatResult] = OrderedDict()
        self._semaphore = asyncio.Semaphore(8)
        self._cooldown_until = now()

    def clear_cache(self):
        self.cache.clear()

    async def check(self, url: str) -> ThreatResult:
        if not self._key:
            return ThreatResult(status="not_configured")
        key = hmac.new(self._salt, url.encode(), hashlib.sha256).hexdigest()
        cached = self.cache.get(key)
        if cached and cached.expires_at and cached.expires_at > now():
            self.cache.move_to_end(key)
            return cached.model_copy(update={"cached": True})
        self.cache.pop(key, None)
        if self._cooldown_until > now():
            return ThreatResult(status="quota", checked_at=now())
        try:
            return await asyncio.wait_for(self._lookup(url, key), timeout=8)
        except asyncio.TimeoutError:
            return ThreatResult(status="timeout", checked_at=now())

    async def _lookup(self, url, cache_key):
        async with self._semaphore:
            async with httpx.AsyncClient(
                timeout=3, follow_redirects=False, trust_env=False, transport=self._transport
            ) as client:
                for attempt in range(2):
                    try:
                        response = await client.post(
                            self.ENDPOINT,
                            params={"key": self._key},
                            json={
                                "client": {"clientId": "lynveris", "clientVersion": "0.1.0"},
                                "threatInfo": {
                                    "threatTypes": [
                                        "MALWARE",
                                        "SOCIAL_ENGINEERING",
                                        "UNWANTED_SOFTWARE",
                                    ],
                                    "platformTypes": ["ANY_PLATFORM"],
                                    "threatEntryTypes": ["URL"],
                                    "threatEntries": [{"url": url}],
                                },
                            },
                            headers={"User-Agent": "Lynveris/0.1"},
                        )
                        client.cookies.clear()
                        checked = now()
                        if response.status_code == 429:
                            self._cooldown_until = checked + timedelta(seconds=60)
                            return ThreatResult(status="quota", checked_at=checked)
                        if response.status_code >= 500 and attempt == 0:
                            await asyncio.sleep(0.1)
                            continue
                        response.raise_for_status()
                        if len(response.content) > 65536:
                            raise ValueError("oversize")
                        body = response.json()
                        if not isinstance(body, dict):
                            raise ValueError("schema")
                        matches = body.get("matches", [])
                        if not isinstance(matches, list) or any(
                            not isinstance(m, dict)
                            or m.get("threatType")
                            not in {"MALWARE", "SOCIAL_ENGINEERING", "UNWANTED_SOFTWARE"}
                            or not isinstance(m.get("cacheDuration"), str)
                            or re.fullmatch(r"[0-9]+(?:\.[0-9]+)?s", m["cacheDuration"]) is None
                            for m in matches
                        ):
                            raise ValueError("schema")
                        ttl = (
                            min(
                                [1800.0]
                                + [float(m["cacheDuration"].removesuffix("s")) for m in matches]
                            )
                            if matches
                            else 60
                        )
                        if ttl <= 0:
                            raise ValueError("expired")
                        result = ThreatResult(
                            status="detected" if matches else "not_found",
                            checked_at=checked,
                            expires_at=checked + timedelta(seconds=ttl),
                            categories=sorted({m["threatType"] for m in matches}),
                            attribution="Advisory provided by Google" if matches else None,
                            advisory_url="https://developers.google.com/safe-browsing/v4/support"
                            if matches
                            else None,
                        )
                        self.cache[cache_key] = result
                        while len(self.cache) > 2048:
                            self.cache.popitem(last=False)
                        return result
                    except httpx.TimeoutException:
                        if attempt == 1:
                            return ThreatResult(status="timeout", checked_at=now())
                    except (httpx.HTTPError, ValueError, KeyError, TypeError, OverflowError):
                        # Never log exceptions: request URLs can contain keys or personal tokens.
                        return ThreatResult(status="error", checked_at=now())
        return ThreatResult(status="error", checked_at=now())
