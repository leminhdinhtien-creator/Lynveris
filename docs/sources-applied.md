# Nguồn đã đọc và áp dụng

Ghi chú kỹ thuật, không phải tổng quan lý thuyết. V4 đã đọc toàn bộ, SafeGuard đổi tên Lynveris, giữ CH1/H1 và CH2/H2; không tạo pilot hoặc số đo H2.

| Nguồn primary đã mở nội dung | Áp dụng trong code/test |
|---|---|
| [Ma et al. KDD2009](https://cseweb.ucsd.edu/~jtma/papers/beyondbl-kdd2009.pdf) | `features.py`: URL/host/path structure, entropy; so sánh Logistic/boosting. Không lấy accuracy paper làm số đo sản phẩm; không giả host-age/HTML. |
| [PhreshPhish publisher](https://huggingface.co/datasets/phreshphish/phreshphish), [paper](https://arxiv.org/html/2507.10854v2) | Metadata-only pinned collector, exact publisher labels/CC BY4, date32 riêng, khóa original test; `test_collection.py`, `test_temporal_dates.py`. |
| [PhishTank export](https://phishtank.org/developer_info.php), [API](https://phishtank.org/api_info.php) | Giữ submission/verification trong importer; UA/rate limit. Live bulk HTTP429, không nhận là đã lấy được dữ liệu. |
| [OpenPhish feeds](https://openphish.com/phishing_feeds.html), [terms](https://openphish.com/terms.html) | Fixed endpoint, bounded body/cache/timeout, academic opt-in, không redistribute feed; prospective receipt không phải report/label time. `test_openphish.py`. |
| [Google v4 Lookup](https://developers.google.com/safe-browsing/v4/lookup-api), [appropriate usage](https://developers.google.com/safe-browsing/v4/appropriate-usage), [setup](https://developers.google.com/safe-browsing/v4/get-started) | Lookup không đòi canonicalize/encode lại URL; Google TTL/attribution, real key restricted API, `threats.py`, `combined_sources.py`, provider/combined tests. Không áp hash-canonicalization Update API; trang hashing từng timeout, không nhận là đã đọc. |
| [Unicode UTS39](https://www.unicode.org/reports/tr39/) Section4, data17 | IDNA brand-label skeleton NFD→map→NFD là **tailoring**, chưa full v17 bidiSkeleton/Default_Ignorable/Script_Extensions. Không tuyên bố full conformance; Unicode tự nó không độc hại. `test_urls.py`. |
| [PSL learn](https://publicsuffix.org/learn/), [list](https://publicsuffix.org/list/) | Pinned PUBLIC+PRIVATE suffix boundaries, không safelist; multi-tenant domain tests. |
| [sklearn1.7 CV](https://scikit-learn.org/1.7/modules/cross_validation.html), [threshold](https://scikit-learn.org/1.7/modules/classification_threshold.html), [metrics](https://scikit-learn.org/1.7/modules/model_evaluation.html) | Installed1.7.2: calendar time+group split, validation-only threshold, độc lập test, unknown denominator và confusion metrics. `test_ml.py`, `test_evaluation_reporting.py`. |

[PhishVN datasheet](https://raw.githubusercontent.com/vuthainguyen1602/phishvn/master/docs/datasheet.md) đã đọc để loại khỏi corpus train này vì provenance/label scope/time; ScienceDirect full article403 không nhận là đã đọc. [IANA example domains](https://www.iana.org/help/example-domains) xác nhận example.org dùng làm đối chứng, không dùng danh tiếng miền để auto-gán benign cho URL tuỳ ý.
