import httpx
import pytest

from lynveris.threats import GoogleSafeBrowsing


@pytest.mark.asyncio
async def test_missing_key_is_not_clear():
    source = GoogleSafeBrowsing("")
    assert (await source.check("https://example.com")).status == "not_configured"


@pytest.mark.parametrize("status,expected", [(429, "quota"), (403, "error"), (500, "error")])
async def test_provider_errors_never_clear(status, expected):
    source = GoogleSafeBrowsing(
        "test", transport=httpx.MockTransport(lambda r: httpx.Response(status))
    )
    assert (await source.check("https://example.com")).status == expected


async def test_timeout_and_no_cookie_or_redirects():
    def respond(request):
        assert "cookie" not in request.headers
        raise httpx.ReadTimeout("test")

    source = GoogleSafeBrowsing("test", transport=httpx.MockTransport(respond))
    assert (await source.check("https://example.com")).status == "timeout"


async def test_detection_cache_expiry_and_source_time():
    calls = []

    def respond(request):
        calls.append(request)
        return httpx.Response(
            200, json={"matches": [{"threatType": "SOCIAL_ENGINEERING", "cacheDuration": "300s"}]}
        )

    source = GoogleSafeBrowsing("test", transport=httpx.MockTransport(respond))
    a = await source.check("https://example.com/private?token=secret")
    b = await source.check("https://example.com/private?token=secret")
    assert a.status == "detected" and b.cached and len(calls) == 1
    assert a.checked_at == b.checked_at and a.expires_at > a.checked_at
    assert "secret" not in repr(source.cache)


async def test_no_match_is_distinct():
    source = GoogleSafeBrowsing(
        "test", transport=httpx.MockTransport(lambda r: httpx.Response(200, json={}))
    )
    assert (await source.check("https://example.com")).status == "not_found"


async def test_malformed_response_is_error():
    source = GoogleSafeBrowsing(
        "test",
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"matches": "garbage"})),
    )
    assert (await source.check("https://example.com")).status == "error"


@pytest.mark.parametrize(
    "matches",
    [
        None,
        [{"threatType": "SOCIAL_ENGINEERING", "cacheDuration": 123}],
        [{"threatType": "SOCIAL_ENGINEERING", "cacheDuration": "NaNs"}],
        [{"threatType": "unexpected", "cacheDuration": "300s"}],
    ],
)
async def test_invalid_provider_fields_degrade_gracefully(matches):
    source = GoogleSafeBrowsing(
        "test",
        transport=httpx.MockTransport(lambda r: httpx.Response(200, json={"matches": matches})),
    )
    assert (await source.check("https://example.com")).status == "error"
