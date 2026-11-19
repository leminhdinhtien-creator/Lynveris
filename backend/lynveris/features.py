import math
from collections import Counter
from urllib.parse import unquote

from .urls import inspect_url, parse_url

FEATURE_VERSION = "url-v1"


def features(url: str) -> dict[str, float]:
    p = parse_url(url)
    inspected = inspect_url(p)
    counts = Counter(p.hostname)
    entropy = -sum((n / len(p.hostname)) * math.log2(n / len(p.hostname)) for n in counts.values())
    return {
        "url_length": len(url),
        "host_length": len(p.hostname),
        "path_length": len(p.path),
        "query_length": len(p.query),
        "host_labels": p.hostname.count(".") + 1,
        "subdomain_depth": p.subdomain.count(".") + bool(p.subdomain),
        "hyphens": p.hostname.count("-"),
        "digits": sum(c.isdigit() for c in p.hostname),
        "entropy": entropy,
        "is_ip": int(p.is_ip),
        "has_userinfo": int(p.has_userinfo),
        "https": int(p.scheme == "https"),
        "percent_count": url.count("%"),
        "query_fields": min(150, p.query.count("&") + bool(p.query)),
        "double_encoding": int("%" in unquote(p.path + p.query)),
        "non_ascii_host": int(any(ord(c) > 127 for c in p.unicode_hostname)),
        "unusual_port": int(p.port not in {None, 80, 443}),
        "strong_signals": sum(s.severity == "strong" for s in inspected.signals),
        "weak_signals": sum(s.severity == "weak" for s in inspected.signals),
        "shortener": int(inspected.shortener),
    }
