"""AI-authored development cases, written before the implementation; not field data."""

import pytest

from lynveris.features import features
from lynveris.urls import UrlError, inspect_url, parse_url, skeleton


@pytest.mark.parametrize(
    "url,host,registered",
    [
        ("https://a.b.example.co.uk/login", "a.b.example.co.uk", "example.co.uk"),
        ("https://alice.github.io/login", "alice.github.io", "alice.github.io"),
        ("https://bob.blogspot.com", "bob.blogspot.com", "bob.blogspot.com"),
        ("https://alice.pages.dev", "alice.pages.dev", "alice.pages.dev"),
        ("https://google.com@evil.example/x", "evil.example", "evil.example"),
        ("https://BÜCHER.de:443/a?x=%252f#frag", "xn--bcher-kva.de", "xn--bcher-kva.de"),
        ("http://[2606:4700:4700::1111]/", "2606:4700:4700::1111", None),
        ("https://example.com./", "example.com", "example.com"),
    ],
)
def test_parser(url, host, registered):
    p = parse_url(url)
    assert p.hostname == host
    assert p.registered_domain == registered
    assert p.original == url


@pytest.mark.parametrize(
    "url",
    [
        "",
        "javascript:alert(1)",
        "file:///etc/passwd",
        "ftp://example.com",
        "example.com",
        "https:///x",
        "https://a.com:bad/",
        "https://a.com:99999/",
        "https://a.com\\@evil.com",
        "https://a.com\n.evil.com",
        "https://%65xample.com/",
        "https://a b.com",
        "https://a.com/%zz",
        "http://2130706433/",
        "http://0177.0.0.1/",
        "http://0x7f000001/",
    ],
)
def test_ambiguous_or_invalid_inputs_rejected(url):
    with pytest.raises(UrlError):
        parse_url(url)


def test_components_remain_distinct_and_encoding_not_rewritten():
    p = parse_url("https://user:secret@example.com:8443/a%252f?next=%252f#bank")
    assert p.port == 8443 and p.has_userinfo
    assert p.path == "/a%252f" and p.query == "next=%252f" and p.fragment == "bank"
    assert p.fetch_url == "https://user:secret@example.com:8443/a%252f?next=%252f"


@pytest.mark.parametrize(
    "url",
    [
        "https://bücher.de",
        "https://tiếngviệt.vn",
        "https://例子.中国",
        "https://παράδειγμα.gr",
        "https://accounts.google.com/login?continue=" + "a" * 400,
        "https://example.org/verify?tracking=" + "0" * 200,
        "http://example.org",
        "https://paypal.com.example.org/news",
        "https://bit.ly/hello",
    ],
)
def test_weak_signals_never_alone_imply_phishing(url):
    r = inspect_url(parse_url(url))
    assert not any(s.severity == "strong" for s in r.signals)


def test_unicode_homograph_and_character_evidence():
    r = inspect_url(parse_url("https://аррӏе.com/login"))
    signal = next(s for s in r.signals if s.code == "brand_homograph")
    assert "apple" in signal.detail.lower()
    assert "U+" in signal.detail
    assert skeleton("аррӏе") == skeleton("apple")


@pytest.mark.parametrize(
    "url,code",
    [
        ("https://paypa1.com/login", "brand_homograph"),
        ("https://gooogle.com/signin", "brand_typo"),
        ("https://vietcombank-xacminh.example/login", "brand_combo"),
        ("https://google.com@evil.example/login", "misleading_userinfo"),
        ("https://accounts.google.com.evil.example/login", "brand_subdomain"),
    ],
)
def test_impersonation(url, code):
    assert code in [s.code for s in inspect_url(parse_url(url)).signals]


def test_official_host_does_not_bypass_inspection():
    r = inspect_url(parse_url("https://accounts.google.com/url?url=https%3A%2F%2Fevil.example"))
    assert "embedded_destination" in [s.code for s in r.signals]


def test_feature_schema_stable_and_no_nan():
    f = features("https://example.com/login?token=x")
    assert f["url_length"] > 0 and f["has_userinfo"] == 0
    assert all(isinstance(x, (int, float)) for x in f.values())
