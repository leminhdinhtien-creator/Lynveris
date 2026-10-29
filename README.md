# Lynveris

Ứng dụng Android giúp gia đình kiểm tra đường link trong tin nhắn, nhìn rõ hostname thực tế và hiểu lý do cần thận trọng. Flutter → FastAPI → phân tích cấu trúc URL, Unicode, mô hình nếu đã được huấn luyện, và nguồn tin đe doạ khi người dùng bật tra nguồn. Có adapter Google Safe Browsing và OpenPhish Community cho nghiên cứu học thuật/cá nhân. Không cần tài khoản; không đọc SMS, danh bạ hoặc clipboard trong nền; không tự mở link.

**Trạng thái local 29/10/2026:** PostgreSQL 18 đã kết nối bằng role riêng; API đang dùng HistGradientBoosting thật từ metadata PhreshPhish có nhãn và ngày thu thập. Google Safe Browsing và OpenPhish chạy kết hợp thật, khoá chỉ lưu local. Test độc lập 14.073 đầu vào: recall 78,00%, precision 95,81%, FPR **5,03%**, chưa đạt mục tiêu 5%. Model ở mức thử nghiệm, không tuyên bố đạt H1. Thiếu timestamp gán nhãn chính xác và blacklist lịch sử nên chỉ là benchmark hồi cứu theo ngày thu dữ liệu. [Chi tiết model/dữ liệu](docs/model-run-20261029.md), [nguồn áp dụng](docs/sources-applied.md). Model/corpus/secret local không nằm trong Git; checkout mới không tự có model.

Đề tài: **Phát triển Lynveris: ứng dụng cảnh báo đường link lừa đảo trong tin nhắn cho gia đình dựa trên đặc trưng URL và nguồn tin đe doạ.** Tên SafeGuard trong V4 được đổi thành Lynveris theo yêu cầu hiện tại. CH1/H1 về phát hiện URL mới và CH2/H2 về khả năng nhận diện của người dùng được giữ nguyên; chưa có kết quả thực nghiệm cho hai giả thuyết. Repository chỉ triển khai sản phẩm và tài liệu kỹ thuật.

## Chạy nhanh trên Windows

Cần Python 3.10–3.12, Git, Flutter 3.47.4/Dart đi kèm, Android SDK và JDK tương thích. Lệnh dưới đây chạy từ thư mục repository trong PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.lock
.\.venv\Scripts\python.exe -m pip install --no-deps -e backend
Copy-Item .env.example .env
.\.venv\Scripts\python.exe -m alembic -c backend/alembic.ini upgrade head
.\.venv\Scripts\python.exe -m uvicorn lynveris.api:app --host 127.0.0.1 --port 8000 --no-access-log --no-proxy-headers
```

Không ghi đè `.env` hiện có. Mặc định dùng SQLite cho phát triển; PostgreSQL là cấu hình Compose. Có thể chạy `scripts/start-dev.ps1` sau khi cài đặt. API health: `http://127.0.0.1:8000/health`, trạng thái DB/model/nguồn: `/ready`, OpenAPI: `/docs`.

Mở terminal khác:

```powershell
cd mobile
flutter pub get
flutter run -d <android-device-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

`10.0.2.2` là địa chỉ host từ Android Emulator. Điện thoại USB có thể dùng `adb reverse tcp:8000 tcp:8000` và chọn API `http://127.0.0.1:8000` trong Cài đặt. Điện thoại qua Internet cần backend HTTPS thật. Ứng dụng từ chối HTTP công khai; Android chỉ cho HTTP ở ba host phát triển localhost, 127.0.0.1 và 10.0.2.2.

Flutter Analyzer/Kotlin trên Windows có thể gặp lỗi đường dẫn có dấu hoặc cache giữa hai ổ đĩa. Có thể dùng thư mục checkout có đường dẫn ASCII hoặc tạo `subst` ở một ổ còn trống rồi chạy Flutter tại đường dẫn đó. Dự án đã tắt incremental Kotlin và giới hạn Gradle workers để xử lý lỗi cache khác ổ quan sát trên máy phát triển. Dùng `dart` nằm trong SDK Flutter, tránh bản Dart độc lập trên PATH.

## PostgreSQL đã cài trên Windows

Với database `lynveris` đã tạo trên `127.0.0.1:5432`, chạy `python scripts/configure_local_postgres.py` bằng Python của `.venv`. Cửa sổ local nhận mật khẩu quản trị bằng ô che ký tự; mật khẩu đó chỉ ở bộ nhớ. Công cụ chạy Alembic bằng kết nối quản trị, tạo một role ứng dụng riêng với CONNECT/USAGE/SELECT/INSERT/DELETE và ghi `.env` bị gitignore, giới hạn ACL cho tài khoản Windows hiện tại và SYSTEM. Không reset schema, sửa pg_hba hoặc thay mật khẩu role có sẵn. Nếu đã có `.env`, công cụ dừng để đối chiếu, không ghi đè.

`python scripts/smoke_database.py` tạo mã sở hữu ngẫu nhiên, kiểm tra ghi/đọc SQL/xoá đúng bản ghi thử và xác nhận các ID có sẵn còn nguyên. Chế độ `LYNVERIS_RETENTION_CLEANUP_ENABLED=false` dành riêng cho phiên kiểm tra bảo toàn dữ liệu; khi dùng bình thường, bật lại cơ chế xoá thống kê sau 7 ngày. Không mở PostgreSQL ra Internet.

## Nguồn tin đe doạ

OpenPhish Community không cần khoá. Chỉ dùng cho nghiên cứu học thuật/cá nhân theo [điều khoản hiện hành](https://openphish.com/terms.html), không phân phối lại feed hoặc dùng thương mại nếu chưa có chấp thuận phù hợp. Chọn `LYNVERIS_THREAT_PROVIDER=openphish` và `LYNVERIS_OPENPHISH_ACADEMIC_USE=true` ở backend. URL người dùng được đối chiếu tại backend, không gửi đến OpenPhish. Backend chỉ tải endpoint HTTPS cố định được liên kết từ [trang feed chính thức](https://openphish.com/phishing_feeds.html); không truy cập các URL trong feed, lưu tập hash trong RAM tối đa một giờ, giới hạn 2 MiB/10.000 dòng, hai lần thử/8 giây và cooldown khi lỗi/quota. Feed Community có phạm vi hạn chế và chu kỳ công bố 12 giờ; không có trong feed không chứng minh hợp lệ. Thời điểm nhận feed không phải thời điểm URL được phát hiện hoặc gán nhãn; không dùng nó tạo timestamp lịch sử cho ML. Không đóng gói feed trong source/APK.

### Google Safe Browsing

Tạo khoá backend theo [tài liệu chính thức](https://developers.google.com/safe-browsing/v4/lookup-api), bật dịch vụ và cấu hình `LYNVERIS_GOOGLE_API_KEY` cùng `LYNVERIS_THREAT_PROVIDER=google` trong `.env`. Không gửi khoá vào chat, commit hoặc APK. Khởi động lại API; người dùng bật **Tra nguồn tin đe doạ** trong Cài đặt sau khi đọc nội dung gửi dữ liệu. API key không được yêu cầu để phân tích cấu trúc URL hoặc dùng OpenPhish cho nghiên cứu.

Máy local đã tạo khoá giới hạn cho Safe Browsing API, không cần nhập lại. `LYNVERIS_THREAT_PROVIDER=combined` dùng Google và OpenPhish song song (cần academic opt-in). Chi tiết hiện trạng thái từng nguồn, không che một nguồn lỗi thành kết quả hai nguồn không phát hiện. Chỉ Google hit mới có attribution Google.

Safe Browsing dùng cho mục đích phi thương mại theo [điều khoản](https://developers.google.com/safe-browsing/v4/terms). Nếu chuyển sang sản phẩm thương mại cần chọn dịch vụ có điều khoản phù hợp. Cache tuân thủ thời hạn; cảnh báo Google có attribution và URL advisory. Chưa ghi nhận trong nguồn không đồng nghĩa an toàn. Thiếu khoá, timeout, quota và lỗi đều được trả riêng, không thay bằng kết quả giả.

## Docker và PostgreSQL

```powershell
Copy-Item .env.example .env
# Sửa POSTGRES_PASSWORD thành chuỗi ngẫu nhiên dài dạng URL-safe trong .env.
docker compose up --build -d --wait api
docker compose logs --tail 50 api
```

Compose chạy PostgreSQL 18, migrations trước API và health checks. Cổng DB không công khai; API bind 127.0.0.1:8000. Trên Linux dùng cùng lệnh với `cp` thay `Copy-Item`. Dừng bằng `docker compose down`; volume DB vẫn được giữ. Chỉ xoá volume nếu muốn xoá vĩnh viễn dữ liệu cục bộ đã biết rõ. Máy thực hiện bàn giao chưa cài Docker; build và chạy Compose đã đạt trên GitHub CI, cùng kiểm thử PostgreSQL native riêng tại máy.

## Kiểm tra và build

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests -q
.\.venv\Scripts\python.exe -m ruff check backend scripts
.\.venv\Scripts\python.exe -m ruff format --check backend scripts
cd mobile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
..\scripts\test-android-product.ps1 -Device <emulator-id> -MobileDirectory (Get-Location).Path
flutter build apk --debug
flutter build web --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

`api_flow_test.dart` dành cho backend không-model/không-tra-nguồn. `product_flow_test.dart` dành cho model thật, hai nguồn và PostgreSQL. **Chạy qua `scripts/test-android-product.ps1`**: prebuild và kiểm tra package QA trước khi khởi động Flutter test, tránh runner ghi nhớ APK chính cũ rồi gỡ nhầm khi kết thúc. Gradle nhận cả target test và define tích hợp do Flutter3.47 tự thêm, không chỉ biến môi trường. Native guard kiểm tra package trước khi đọc/ghi preferences. Collector nhận `--product --package vn.lynveris.lynveris.qa`. Không chạy lệnh integration trực tiếp khi APK hiện tại là package chính. Ví dụ ca không-model chỉ sau khi đã prebuild/kiểm tra QA:

```powershell
# Terminal 1, tại root: chờ và thu đúng 3 ảnh do test tạo trong app debug.
.\.venv\Scripts\python.exe scripts/collect_test_screenshots.py <emulator-id>
# Terminal 2, tại mobile:
$env:ORG_GRADLE_PROJECT_lynverisQa='true'
flutter test integration_test/api_flow_test.dart -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000 --dart-define=CAPTURE_QA=true
```

Ảnh được lưu trong `artifacts/screenshots/`. APK thường ở `mobile/build/app/outputs/flutter-apk/app-debug.apk`; bản bàn giao được sao chép sang `artifacts/lynveris-debug.apk`. Đây là APK debug để thử nghiệm, không phải bản phát hành có chữ ký sản xuất. Sau khi chạy integration test, cần build lại ứng dụng thường trước khi lấy APK bàn giao để tránh đóng gói test runner. Muốn phát hành phải cấu hình signing riêng, backend HTTPS và hoàn tất đánh giá dữ liệu.

Build release được chặn khi chưa có `mobile/android/key.properties`. File riêng này cần `storeFile` (đường dẫn keystore), `storePassword`, `keyAlias`, `keyPassword`; tất cả đều bị gitignore. Không dùng debug key để giả làm bản phát hành. Không đưa keystore hoặc mật khẩu vào mã nguồn.

Web chỉ phục vụ xem thử/kiểm tra cùng mã Flutter, không thay thế ứng dụng Android. Chạy `python -m http.server 8080 --bind 127.0.0.1 --directory mobile/build/web` từ root, mở `http://127.0.0.1:8080`. Dùng đúng origin đã khai báo CORS. Không có mock backend trong bản chạy.

## Dữ liệu và mô hình

[Hướng dẫn dữ liệu và mô hình](docs/data-and-model.md) mô tả collector, schema nhãn/timestamp, khử trùng, PSL/private hosting, nhóm chiến dịch, tách thời gian, blacklist baseline, Logistic Regression/boosting, chọn ngưỡng trên validation và test độc lập khoá một lần. Không có model artifact mẫu trong sản phẩm. Bộ dữ liệu UCI đã tải có nhãn thật nhưng thiếu timestamp từng dòng, vì vậy chỉ được cách ly; không thay bằng ngày tải.

Chỉ load artifact do bạn tin cậy tạo. Khi đã có artifact đáp ứng điều kiện, đặt `LYNVERIS_MODEL_DIRECTORY` tới thư mục chứa `model.joblib` và `manifest.json`, dùng đúng phiên bản thư viện/tham chiếu đã huấn luyện, rồi khởi động lại API. Kết quả gồm phiên bản model, feature, policy và ngưỡng để truy vết.

## Quyền riêng tư và giới hạn

Lịch sử và thống kê mặc định tắt. Lịch sử chỉ ở thiết bị, bỏ toàn bộ path/query/fragment/userinfo, tối đa 100 mục/30 ngày; có xoá từng mục hoặc tất cả. Thống kê tự nguyện không chứa URL/tin nhắn/IP, có mã xoá riêng và thời hạn 7 ngày. Clipboard chỉ đọc khi bấm Dán. Chia sẻ kết quả chỉ xảy ra qua thao tác của người dùng và không kèm token hoặc nội dung tin nhắn.

Không truy cập URL đích, không giải quyết chuyển hướng/link rút gọn, không đánh giá nội dung trang, DNS/tuổi miền/chứng chỉ. Ứng dụng nêu rõ các giới hạn này. Phân tích URL có thể bỏ sót hoặc cảnh báo nhầm; không có nhãn “an toàn tuyệt đối”. [Kiến trúc và vận hành](docs/architecture.md) giải thích trạng thái kết quả, bảo mật, dữ liệu lưu và các bước triển khai.

## Cấu trúc mã nguồn

```text
mobile/lib/              Flutter UI, API client, trích URL, lưu trên thiết bị
mobile/integration_test/ Luồng Android đến API thật
backend/lynveris/        API, parser, đặc trưng, tổng hợp, provider, model, dữ liệu
backend/lynveris/ml/     Tách tập, train, đánh giá độc lập
backend/tests/          Unit, API, provider mock, hồi quy, pipeline
backend/migrations/     Alembic PostgreSQL
scripts/                Collector/import/snapshot, chạy dev, smoke DB
.github/workflows/      Lint, test, PostgreSQL, Docker, Flutter build
```

Các test được AI hỗ trợ viết trước phần triển khai tương ứng và bổ sung theo lỗi quan sát; không nhận là test do sinh viên tự viết. Không tạo phỏng vấn, pilot hoặc chỉ số nghiên cứu giả. Giấy phép dữ liệu và thư viện nằm trong [Third party notices](THIRD_PARTY_NOTICES.md).
