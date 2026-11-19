"""Run the W05 functional cases against the existing local API.

This suite checks API contracts and URL evidence. It never trains the model
or evaluates the locked research holdout.
"""

import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx


def main():
    output = Path("artifacts/w05")
    output.mkdir(parents=True, exist_ok=True)
    cases = [
        ("E01", "Trang đối chứng IANA", "https://www.iana.org/help/example-domains", "Đối chứng tài liệu", 200, "www.iana.org", None),
        ("E02", "Kênh học AWS Academy", "https://awsacademy.instructure.com/", "Trang đang dùng", 200, "awsacademy.instructure.com", None),
        ("E03", "Mẫu cảnh báo Google", "https://testsafebrowsing.appspot.com/s/phishing.html", "Mẫu thử chính thức Google", 200, "testsafebrowsing.appspot.com", "threat_match"),
        ("E04", "Thương hiệu trước dấu @", "https://paypal.com@verify.example.org/login", "URL mô phỏng", 200, "verify.example.org", "misleading_userinfo"),
        ("E05", "Thương hiệu trong tên miền phụ", "https://paypal.com.verify.example.org/login", "URL mô phỏng", 200, "paypal.com.verify.example.org", "brand_subdomain"),
        ("E06", "Tên miền giống thương hiệu", "https://аррӏе.com/login", "URL mô phỏng Unicode", 200, None, "brand_homograph"),
        ("E07", "Thương hiệu trong đường dẫn", "https://example.org/paypal/login", "URL mô phỏng", 200, "example.org", "brand_path"),
        ("E08", "Link rút gọn chưa rõ đích", "https://bit.ly/lynveris-example", "URL mô phỏng", 200, "bit.ly", "shortener"),
        ("E09", "Địa chỉ dùng HTTP", "http://example.org/", "Đối chứng giao thức", 200, "example.org", "unencrypted"),
        ("E10", "Địa chỉ IP riêng", "http://192.168.1.1/login", "URL mô phỏng nội bộ", 200, "192.168.1.1", "non_public_address"),
        ("E11", "Địa chỉ khác trong query", "https://example.org/?next=https%3A%2F%2Faccount.example.net%2Fverify", "URL mô phỏng", 200, "example.org", "embedded_destination"),
        ("E12", "Đầu vào rỗng", "", "Đầu vào không hỗ trợ", 422, None, None),
        ("E13", "Thiếu giao thức", "awsacademy.instructure.com", "Đầu vào không hỗ trợ", 422, None, None),
        ("E14", "Giao thức tệp", "file:///private/document", "Đầu vào không hỗ trợ", 422, None, None),
        ("E15", "Mã phần trăm sai", "https://example.org/%ZZ", "Đầu vào không hỗ trợ", 422, None, None),
        ("E16", "Cổng vượt phạm vi", "https://example.org:99999/", "Đầu vào không hỗ trợ", 422, None, None),
    ]
    records = []
    with httpx.Client(timeout=18, follow_redirects=False) as client:
        for case_id, name, url, origin, expected_http, host, signal in cases:
            started = time.perf_counter()
            response = client.post("http://127.0.0.1:8000/v1/check", json={
                "url": url, "use_threat_intelligence": True, "research_consent": False,
            })
            body = response.json()
            codes = [s["code"] for s in body.get("signals", [])]
            passed = response.status_code == expected_http
            if expected_http == 200:
                passed = passed and (host is None or body["url"]["hostname"] == host)
                passed = passed and (signal is None or signal in codes)
            records.append({
                "id": case_id, "name": name, "origin": origin, "input": url,
                "expected_http": expected_http, "expected_host": host, "expected_signal": signal,
                "http": response.status_code, "verdict": body.get("verdict"),
                "signals": codes, "elapsed_seconds": round(time.perf_counter() - started, 3),
                "passed": passed, "response": body,
            })
        response = client.post("http://127.0.0.1:8000/v1/check", json={
            "url": cases[0][2], "use_threat_intelligence": False, "research_consent": False,
        })
        body = response.json()
        records.append({"id": "E17", "name": "Người dùng tắt tra nguồn", "input": cases[0][2],
                        "http": response.status_code, "verdict": body.get("verdict"),
                        "passed": body.get("threat", {}).get("status") == "skipped", "response": body})
        response = client.post("http://127.0.0.1:8003/v1/check", json={
            "url": cases[0][2], "use_threat_intelligence": True, "research_consent": False,
        })
        body = response.json()
        records.append({"id": "E18", "name": "Nguồn Google chưa cấu hình", "input": cases[0][2],
                        "http": response.status_code, "verdict": body.get("verdict"),
                        "passed": body.get("threat", {}).get("partial") is True and body.get("verdict") == "insufficient",
                        "response": body})
    baseline = json.loads(Path(".verification/release-baseline.json").read_text(encoding="utf-8-sig"))
    integrity = {
        name: hashlib.sha256(Path(name).read_bytes()).hexdigest() == expected
        for name, expected in baseline["files"].items()
    }
    report = {"checked_at": datetime.now(timezone.utc).isoformat(),
              "scope": "W05 functional API checks, separate from locked research evaluation",
              "total": len(records), "passed": sum(r["passed"] for r in records),
              "locked_files_unchanged": integrity, "cases": records}
    (output / "eval-w05.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"total": report["total"], "passed": report["passed"], "locked_files": all(integrity.values()),
                      "failed": [r["id"] for r in records if not r["passed"]]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
