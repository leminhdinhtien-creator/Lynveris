"""Synthetic development cases, not benchmark labels and not observed user mistakes."""

import pytest

from lynveris.urls import UrlError, inspect_url, parse_url

CASES = [
    ("https://accounts.google.com/signin", False),
    ("https://www.paypal.com/signin", False),
    ("https://support.apple.com/vi-vn", False),
    ("https://vcbdigibank.vietcombank.com.vn", False),
    ("https://bücher.de/login", False),
    ("https://tiếngviệt.vn/đăng-nhập", False),
    ("https://例子.中国/verify", False),
    ("https://παράδειγμα.gr/login", False),
    ("https://alice.github.io/account", False),
    ("https://bob.pages.dev/google", False),
    ("https://company.blogspot.com/promo", False),
    ("https://example.co.uk/login", False),
    ("https://example.com.vn/verify", False),
    ("https://example.com/?campaign=google&tracking=12345", False),
    ("http://example.com/login", False),
    ("https://bit.ly/official-promotion", False),
    ("https://tinyurl.com/promotion", False),
    ("https://t.co/example", False),
    ("https://example.com/" + "a" * 1000, False),
    ("https://example.org/?url=https%3A%2F%2Faccounts.google.com", False),
    ("https://apple.news/", False),
    ("https://appletree.example/news", False),
    ("https://google.com.example.org/news", False),
    ("https://google.com@evil.example/login", True),
    ("https://paypal.com@evil.example/account", True),
    ("https://paypa1.com/login", True),
    ("https://аррӏе.com/login", True),
    ("https://gοοgle.com/login", True),
    ("https://gooogle.com/verify", True),
    ("https://goolge.com/login", True),
    ("https://vietcombank-xacminh.example/", True),
    ("https://paypal-secure.example/login", True),
    ("https://accounts.google.com.evil.example/login", True),
    ("https://paypal.evil.example/verify", True),
    ("https://user:pass@example.com/", False),
    ("http://127.0.0.1/", False),
    ("http://[::1]/", False),
    ("http://169.254.169.254/latest/meta-data", False),
]


@pytest.mark.parametrize("url,strong", CASES)
def test_development_regression(url, strong):
    assert any(s.severity == "strong" for s in inspect_url(parse_url(url)).signals) == strong


def test_many_query_fields_and_encoded_reserved_characters_do_not_crash():
    url = "https://example.com/?" + "&".join(f"k{i}=x" for i in range(250))
    assert inspect_url(parse_url(url)) is not None


@pytest.mark.parametrize("url", ["https://example.com/\u202esecret", "https://example.com/\x00"])
def test_hidden_controls_are_not_silently_stripped(url):
    with pytest.raises(UrlError):
        parse_url(url)
