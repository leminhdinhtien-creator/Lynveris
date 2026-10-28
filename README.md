# Lynveris

Ứng dụng Android giúp gia đình kiểm tra đường link trong tin nhắn, nhìn rõ hostname thực tế và hiểu lý do cần thận trọng. Flutter → FastAPI → phân tích cấu trúc URL, Unicode, mô hình nếu đã được huấn luyện, và Google Safe Browsing khi người dùng bật tra nguồn. Không cần tài khoản; không đọc SMS, danh bạ hoặc clipboard trong nền; không tự mở link.

**Trạng thái:** có luồng ứng dụng/API chạy thật, bộ phân tích, lịch sử tuỳ chọn, chia sẻ hệ điều hành, PostgreSQL migrations, pipeline train/evaluate, Docker Compose và CI. Chưa có model được huấn luyện trên bộ dữ liệu thật đủ timestamp; chưa xác minh Google live vì chưa cấu hình API key. Không tuyên bố đạt recall +30 điểm phần trăm hoặc FPR ≤5%. [Kết quả kiểm tra và giới hạn](docs/verification.md) ghi riêng từng phần đã xác minh.

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

## Google Safe Browsing

Tạo khoá backend theo [tài liệu chính thức](https://developers.google.com/safe-browsing/v4/lookup-api), bật dịch vụ và cấu hình `LYNVERIS_GOOGLE_API_KEY` trong `.env`. Không gửi khoá vào chat, commit hoặc APK. Khởi động lại API; người dùng bật **Tra Google Safe Browsing** trong Cài đặt sau khi đọc nội dung gửi dữ liệu. API key không được yêu cầu để phân tích cấu trúc URL.

Safe Browsing dùng cho mục đích phi thương mại theo [điều khoản](https://developers.google.com/safe-browsing/v4/terms). Nếu chuyển sang sản phẩm thương mại cần chọn dịch vụ có điều khoản phù hợp. Cache tuân thủ thời hạn; cảnh báo Google có attribution và URL advisory. Chưa ghi nhận trong nguồn không đồng nghĩa an toàn. Thiếu khoá, timeout, quota và lỗi đều được trả riêng, không thay bằng kết quả giả.

## Docker và PostgreSQL

```powershell
Copy-Item .env.example .env
# Sửa POSTGRES_PASSWORD thành chuỗi ngẫu nhiên dài dạng URL-safe trong .env.
docker compose up --build -d --wait api
docker compose logs --tail 50 api
```

Compose chạy PostgreSQL 18, migrations trước API và health checks. Cổng DB không công khai; API bind 127.0.0.1:8000. Trên Linux dùng cùng lệnh với `cp` thay `Copy-Item`. Dừng bằng `docker compose down`; volume DB vẫn được giữ. Chỉ xoá volume nếu muốn xoá vĩnh viễn dữ liệu cục bộ đã biết rõ. Máy thực hiện bàn giao chưa cài Docker, nên việc chạy container được để CI xác minh; kiểm thử PostgreSQL native đã chạy riêng.

## Kiểm tra và build

```powershell
.\.venv\Scripts\python.exe -m pytest backend/tests -q
.\.venv\Scripts\python.exe -m ruff check backend scripts
.\.venv\Scripts\python.exe -m ruff format --check backend scripts
cd mobile
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter test integration_test/api_flow_test.dart -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter build apk --debug
flutter build web --no-web-resources-cdn --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Integration test cần API thật đang chạy, không cấu hình model và không bật Google. Nó xác minh kết quả thiếu thông tin và hostname giả mạo trước dấu @. Để thu ảnh giao diện từ thiết bị kiểm thử:

```powershell
# Terminal 1, tại root: chờ và thu đúng 3 ảnh do test tạo trong app debug.
.\.venv\Scripts\python.exe scripts/collect_test_screenshots.py <emulator-id>
# Terminal 2, tại mobile:
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
