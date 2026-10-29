"""Transport fixtures exercise failures; actual feed verification is a separate local smoke."""

from datetime import datetime, timedelta, timezone

import httpx
import pytest

from lynveris.openphish import OpenPhishCommunity


@pytest.mark.asyncio
async def test_feed_lookup_is_exact_private_and_cached():
    requests = []

    def serve(request):
        requests.append(request)
        return httpx.Response(200, text="https://bad.example/login?x=1\nhttps://other.example/\n")

    source = OpenPhishCommunity(True, transport=httpx.MockTransport(serve))
    found = await source.check("https://bad.example/login?x=1")
    assert found.status == "detected" and found.source == "OpenPhish Community"
    assert found.expires_at > found.checked_at
    assert (await source.check("https://bad.example/login?x=2")).status == "not_found"
    assert (await source.check("https://other.example/")).cached
    assert len(requests) == 1
    assert str(requests[0].url) == OpenPhishCommunity.ENDPOINT
    assert not requests[0].content


@pytest.mark.asyncio
async def test_unconfigured_or_unavailable_is_never_clean():
    assert (await OpenPhishCommunity(False).check("https://example.org")).status == "not_configured"
    for response in [
        httpx.Response(503),
        httpx.Response(200, text="<!doctype html>blocked"),
        httpx.Response(
            200,
            text="https://bad.example/\n",
            headers={"Last-Modified": "Mon, 01 Jan 2024 00:00:00 GMT"},
        ),
    ]:
        source = OpenPhishCommunity(True, transport=httpx.MockTransport(lambda request: response))
        assert (await source.check("https://bad.example/")).status == "error"


@pytest.mark.asyncio
async def test_expired_feed_is_not_used_after_outage():
    calls = []

    def serve(request):
        calls.append(1)
        return (
            httpx.Response(200, text="https://bad.example/\n")
            if len(calls) == 1
            else httpx.Response(503)
        )

    source = OpenPhishCommunity(True, transport=httpx.MockTransport(serve))
    assert (await source.check("https://bad.example/")).status == "detected"
    source.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    assert (await source.check("https://bad.example/")).status == "error"


@pytest.mark.asyncio
async def test_timeout_and_quota_have_distinct_status():
    def timeout(request):
        raise httpx.ReadTimeout("fixture timeout")

    assert (
        await OpenPhishCommunity(True, transport=httpx.MockTransport(timeout)).check(
            "https://example.org"
        )
    ).status == "timeout"
    source = OpenPhishCommunity(
        True, transport=httpx.MockTransport(lambda request: httpx.Response(429))
    )
    assert (await source.check("https://example.org")).status == "quota"
