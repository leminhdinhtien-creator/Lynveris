"""Strict URL parsing. Never visit, repair or recursively decode a submitted address."""

import ipaddress
import json
import re
import unicodedata
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from urllib.parse import parse_qsl, unquote, urlsplit, urlunsplit

import idna
import tldextract

from .schemas import Signal

DATA = Path(__file__).with_name("data")
BRANDS = json.loads((DATA / "brands.json").read_text(encoding="utf-8"))
_extract = tldextract.TLDExtract(
    suffix_list_urls=((DATA / "public_suffix_list.dat").as_uri(),),
    cache_dir=None,
    include_psl_private_domains=True,
    fallback_to_snapshot=False,
)
SHORTENERS = frozenset(
    {
        "bit.ly",
        "tinyurl.com",
        "t.co",
        "goo.gl",
        "shorturl.at",
        "is.gd",
        "buff.ly",
        "cutt.ly",
        "rebrand.ly",
        "rb.gy",
        "s.id",
        "lnkd.in",
    }
)
CONTEXT = re.compile(r"login|signin|verify|secure|account|xacminh|dangnhap|giaohang|delivery", re.I)


class UrlError(ValueError):
    pass


@dataclass(frozen=True)
class ParsedUrl:
    original: str
    hostname: str
    unicode_hostname: str
    registered_domain: str | None
    suffix: str
    domain_label: str
    subdomain: str
    scheme: str
    port: int | None
    path: str
    query: str
    fragment: str
    has_userinfo: bool
    userinfo: str
    fetch_url: str
    is_ip: bool


def parse_url(original: str) -> ParsedUrl:
    if not original or len(original) > 4096:
        raise UrlError("Đường link phải có từ 1 đến 4.096 ký tự.")
    if (
        any(c.isspace() or unicodedata.category(c).startswith("C") for c in original)
        or "\\" in original
    ):
        raise UrlError("Đường link chứa khoảng trắng, ký tự ẩn hoặc dấu gạch chéo không hợp lệ.")
    if re.search(r"%(?![0-9A-Fa-f]{2})", original):
        raise UrlError("Mã phần trăm trong đường link không hợp lệ.")
    try:
        u = urlsplit(original)
        if u.scheme.lower() not in {"http", "https"} or not u.netloc or not u.hostname:
            raise UrlError("Hãy nhập đầy đủ đường link bắt đầu bằng http:// hoặc https://.")
        host = u.hostname.rstrip(".")
        if "%" in host or not host or original.count("@") > 8:
            raise UrlError("Tên miền không hợp lệ hoặc có cách viết dễ gây nhầm lẫn.")
        port = u.port
        is_ip = False
        try:
            address = ipaddress.ip_address(host)
            host = str(address)
            is_ip = True
        except ValueError:
            # Browsers accept alternative numeric IP forms; reject instead of interpreting differently.
            if re.fullmatch(r"[0-9.]+", host) or re.fullmatch(
                r"(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*", host, re.I
            ):
                raise UrlError("Địa chỉ IP viết tắt hoặc không chuẩn không được hỗ trợ.")
        if not is_ip:
            host = (
                idna.encode(host, uts46=True, transitional=False, std3_rules=True)
                .decode("ascii")
                .lower()
            )
            unicode_host = idna.decode(host)
            e = _extract(host)
            registered = e.top_domain_under_public_suffix or host
            label, suffix, subdomain = e.domain, e.suffix, e.subdomain
            if not suffix and "." in host:
                # PSL implicit '*' rule for unknown/reserved TLDs.
                labels = host.split(".")
                label, suffix = labels[-2:]
                registered, subdomain = ".".join(labels[-2:]), ".".join(labels[:-2])
        else:
            unicode_host, registered, label, suffix, subdomain = host, None, host, "", ""
        return ParsedUrl(
            original,
            host,
            unicode_host,
            registered,
            suffix,
            label,
            subdomain,
            u.scheme.lower(),
            port,
            u.path,
            u.query,
            u.fragment,
            "@" in u.netloc,
            u.netloc.rsplit("@", 1)[0] if "@" in u.netloc else "",
            urlunsplit((u.scheme, u.netloc, u.path, u.query, "")),
            is_ip,
        )
    except (ValueError, idna.IDNAError) as exc:
        if isinstance(exc, UrlError):
            raise
        raise UrlError("Không thể đọc tên miền hoặc cổng của đường link này.") from None


@lru_cache(maxsize=1)
def _confusables():
    mapping = {}
    for line in (DATA / "confusables.txt").read_text(encoding="utf-8-sig").splitlines():
        fields = line.split("#")[0].strip().split(";")
        if len(fields) >= 2:
            key = "".join(chr(int(x, 16)) for x in fields[0].split())
            mapping[key] = "".join(chr(int(x, 16)) for x in fields[1].split())
    return mapping


@lru_cache(maxsize=2048)
def skeleton(value: str) -> str:
    # UTS #39 section 4: NFD -> confusables mapping -> NFD. No URL rewriting.
    nfd = unicodedata.normalize("NFD", value)
    return unicodedata.normalize("NFD", "".join(_confusables().get(c, c) for c in nfd))


def edit_distance(a, b):
    # Optimal string alignment (adjacent transpositions included).
    d = [[0] * (len(b) + 1) for _ in range(len(a) + 1)]
    for i in range(len(a) + 1):
        d[i][0] = i
    for j in range(len(b) + 1):
        d[0][j] = j
    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            d[i][j] = min(
                d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] != b[j - 1])
            )
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
    return d[-1][-1]


@dataclass
class Inspection:
    signals: list[Signal]
    shortener: bool


def inspect_url(p: ParsedUrl) -> Inspection:
    signals = []

    def add(code, title, detail, severity="info"):
        signals.append(Signal(code=code, title=title, detail=detail, severity=severity))

    contextual = bool(CONTEXT.search(unquote(p.path + "?" + p.query)))
    if p.has_userinfo:
        brand_in_user = any(t in p.userinfo.lower() for b in BRANDS["brands"] for t in b["tokens"])
        add(
            "misleading_userinfo" if brand_in_user else "userinfo",
            "Có nội dung trước dấu @",
            f"Máy chủ nhận kết nối là {p.hostname}. Nội dung trước @ không phải tên miền đích.",
            "strong" if brand_in_user else "weak",
        )
    if p.is_ip:
        address = ipaddress.ip_address(p.hostname)
        add(
            "ip_host",
            "Đường link dùng địa chỉ IP",
            "Địa chỉ IP không xác minh danh tính của tổ chức.",
            "weak",
        )
        if not address.is_global:
            add(
                "non_public_address",
                "Địa chỉ mạng nội bộ hoặc dành riêng",
                "Lynveris chỉ phân tích văn bản địa chỉ này và không truy cập máy chủ đích.",
                "weak",
            )
    elif (
        p.hostname == "localhost"
        or "." not in p.hostname
        or p.hostname.endswith((".local", ".internal", ".localhost"))
    ):
        add(
            "non_public_address",
            "Tên máy trong mạng nội bộ",
            "Không truy cập hoặc giải quyết địa chỉ nội bộ từ backend.",
            "weak",
        )
    if p.scheme == "http":
        add(
            "unencrypted",
            "Kết nối không dùng HTTPS",
            "HTTP không mã hoá kết nối; riêng điều này chưa chứng minh lừa đảo.",
            "weak",
        )
    shortener = p.hostname in SHORTENERS
    if shortener:
        add(
            "shortener",
            "Đường link rút gọn",
            "Chưa biết địa chỉ cuối. Link rút gọn hợp lệ cũng có đặc điểm này.",
        )
    try:
        unicode_label = idna.decode(p.domain_label) if not p.is_ip else p.domain_label
    except idna.IDNAError:
        unicode_label = p.domain_label
    if any(ord(c) > 127 for c in p.unicode_hostname):
        add(
            "idn",
            "Tên miền quốc tế",
            f"Dạng ASCII: {p.hostname}. Unicode tự nó không phải dấu hiệu lừa đảo.",
        )
    scripts = {unicodedata.name(c, "").split(" ")[0] for c in unicode_label if c.isalpha()}
    if len(scripts & {"LATIN", "CYRILLIC", "GREEK"}) > 1:
        add(
            "mixed_script",
            "Tên miền trộn bảng chữ",
            "Có chữ Latin, Cyrillic hoặc Greek trong cùng nhãn; cần đối chiếu danh tính.",
            "weak",
        )
    for brand in BRANDS["brands"]:
        # Do not exempt paths, parameters or other evidence on an official host.
        official = any(p.hostname == d or p.hostname.endswith("." + d) for d in brand["domains"])
        if official:
            continue
        for token in brand["tokens"]:
            label = unicode_label.lower()
            if label != token and skeleton(label) == skeleton(token):
                changed = [f"{c} (U+{ord(c):04X})" for c in label if c not in token]
                add(
                    "brand_homograph",
                    "Tên miền có ký tự giống thương hiệu",
                    f"Nhãn {unicode_label} trông giống {brand['name']}: {', '.join(changed)}. "
                    f"Miền tham chiếu: {', '.join(brand['domains'])}.",
                    "strong",
                )
            elif 4 < len(label) < 64 and label != token and edit_distance(label, token) <= 1:
                add(
                    "brand_typo",
                    "Tên miền gần giống thương hiệu",
                    f"{unicode_label} cách {token} một thao tác thêm, bớt, đổi hoặc đảo chữ. "
                    "Đây là tín hiệu đối chiếu, không xác nhận chủ sở hữu.",
                    "strong" if contextual else "weak",
                )
            elif token in label and label != token and CONTEXT.search(label):
                add(
                    "brand_combo",
                    "Tên thương hiệu ghép với lời nhắc xác minh",
                    f"Nhãn {unicode_label} chứa {brand['name']} và từ gợi đăng nhập/xác minh, "
                    f"nhưng miền đăng ký là {p.registered_domain}.",
                    "strong",
                )
            if token in p.subdomain.lower().split("."):
                add(
                    "brand_subdomain",
                    "Thương hiệu nằm ở phần tên miền phụ",
                    f"{brand['name']} nằm trước miền đăng ký {p.registered_domain}. "
                    "Tên miền phụ có thể do chủ miền đăng ký tự đặt.",
                    "strong" if contextual else "weak",
                )
            if token in unquote(p.path).lower():
                add(
                    "brand_path",
                    "Thương hiệu xuất hiện trong đường dẫn",
                    f"Tên {brand['name']} trong đường dẫn không xác nhận {p.hostname} thuộc tổ chức đó.",
                    "weak",
                )
    for key, value in parse_qsl(p.query, keep_blank_values=True, max_num_fields=4096)[:150]:
        if value.lower().startswith(("https://", "http://")):
            try:
                dest = parse_url(value)
                add(
                    "embedded_destination",
                    "Có một địa chỉ khác trong tham số",
                    f"Tham số chứa hostname {dest.hostname}. Chưa xác minh trang có chuyển hướng tới đó.",
                    "weak",
                )
            except UrlError:
                pass
    return Inspection(list({s.code + s.detail: s for s in signals}.values()), shortener)
