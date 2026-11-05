# Lynveris 1.0.0

## Bản cài cho giả lập

`lynveris-1.0.0-local.apk` là APK release có chữ ký của dự án, cho Android ARM64 và x86-64. Package `vn.lynveris.lynveris.local` cài riêng với bản debug và package QA. App kết nối `http://10.0.2.2:8000` qua mạng riêng của Android Emulator. Ngoại lệ HTTP chỉ dành cho địa chỉ phát triển cục bộ. Model, khóa tra nguồn và PostgreSQL nằm ở backend.

Tại thư mục repo, dùng `.venv` và `.env` đã cấu hình. Chạy `scripts/start-dev.ps1` để mở API loopback. Trong phiên kiểm thử cần giữ nguyên các bản ghi có sẵn, đặt `LYNVERIS_RETENTION_CLEANUP_ENABLED=false` riêng cho tiến trình API. Cài APK local bằng `adb install -r` trên đúng thiết bị và mở **Lynveris Local**. `/health` trả tên dịch vụ và phiên bản. `/ready` kiểm tra PostgreSQL cùng trạng thái cấu hình model và nguồn.

## Bản cài cho máy chủ HTTPS

`lynveris-1.0.0-https.apk` dùng package chính `vn.lynveris.lynveris`. Bản này yêu cầu HTTPS. Khi chưa biên dịch địa chỉ máy chủ vào APK, màn hình **Kiểm tra** dẫn đến **Thiết lập kết nối**. App kiểm tra `/health` trước khi lưu địa chỉ. Khi build với `--dart-define=API_BASE_URL=https://<máy-chủ>`, địa chỉ cố định cho bản phát hành đó.

Android chỉ chấp nhận cập nhật tại chỗ khi package và chữ ký khớp. Nếu trên thiết bị đã có bản debug cùng package chính, dùng bản local song song khi kiểm thử để giữ dữ liệu debug.

### Build và xác minh chữ ký

Giữ keystore cùng thông tin phục hồi ở nơi chỉ chủ dự án có quyền đọc. Đặt `LYNVERIS_ANDROID_SIGNING_PROPERTIES` đến file properties riêng hoặc cấu hình `mobile/android/key.properties` bị Git bỏ qua. Dùng cùng khóa khi phát hành bản cập nhật. Tài liệu ký APK và AAB: [Flutter Android release](https://docs.flutter.dev/deployment/android).

```powershell
Set-Location mobile
flutter build apk --release --target-platform android-arm64,android-x64 --dart-define=LYNVERIS_LOCAL_RELEASE=true --dart-define=API_BASE_URL=http://10.0.2.2:8000
# Sao chép app-release.apk sang tên có hậu tố -local trước khi build tiếp.
flutter build apk --release --target-platform android-arm64,android-x64
```

Dùng `apksigner verify --print-certs` từ Android SDK Build Tools và `aapt dump badging` để xác minh chữ ký, package, mã phiên bản và ABI. Kiểm tra cấu hình mạng trong AndroidManifest của APK trước khi phân phối.

## Kiểm tra bản cài ngày 05/11/2026

- Small_Phone cài được bản local 1.0.0 và giữ bản debug ở package riêng. Bản local xử lý đầu vào rỗng, gửi URL đối chứng IANA đến API và hiện kết quả thật. Bảng chia sẻ Android hiển thị hostname, thời điểm, kết quả và khuyến nghị.
- Backend có 132 test đạt. Flutter có 18 test đạt và analyzer không báo lỗi. Kiểm tra PostgreSQL ghi, đọc và xoá đúng bản ghi thử. Các ID có sẵn và 9 tệp đã khóa giữ nguyên.
- Caddy đã được kiểm tra với TLS trên loopback. API nạp model 20261029T135127Z và trả trạng thái riêng của Google Safe Browsing và OpenPhish. Proxy từ chối body quá lớn và chặn đường dẫn vận hành nội bộ. Cấu hình máy chủ công khai chờ host và model tương thích.

## Máy chủ cho đợt dùng thử qua Internet

Cần một máy Linux có DNS trỏ tới máy chủ, Caddy 2.11, PostgreSQL với quyền tối thiểu, Python 3.12 được hỗ trợ và model tương thích với runtime. Giữ phiên bản thư viện theo `backend/requirements.lock`. Cấu hình dự án hiện hướng tới nghiên cứu phi thương mại theo [Google Safe Browsing](https://developers.google.com/safe-browsing/v4/terms) và [OpenPhish](https://openphish.com/terms.html).

Model nghiên cứu đã khóa có manifest ghi Python 3.10 và dữ liệu Unicode 13. Python 3.10 đã hết hỗ trợ bảo mật. Dùng runtime cục bộ đó để tái lập kết quả đã ghi. Đợt phát hành qua Internet cần model đã được xác minh với runtime còn hỗ trợ. API từ chối khởi động ở chế độ release nếu model không tương thích. [Lịch hỗ trợ Python 3.10](https://peps.python.org/pep-0619/)

1. Cài repo vào `/opt/lynveris` và tạo `.venv` tại đó. Cài `backend/requirements.lock` rồi cài package `backend`. Tạo tài khoản dịch vụ hệ thống `lynveris`. Cấp quyền đọc mã nguồn, môi trường Python và artifact model cho tài khoản này.
2. Tạo database riêng cho đợt dùng thử. Chạy Alembic bằng tài khoản migration. Cấp cho role chạy API quyền CONNECT, USAGE, SELECT, INSERT và DELETE như phần PostgreSQL trong README. Giữ cổng database riêng tư.
3. Tạo `/etc/lynveris/lynveris.env` từ `deploy/lynveris.env.example` với quyền đọc hạn chế. Điền chuỗi kết nối của role runtime, đường dẫn model tin cậy và cấu hình nguồn. Dùng bản sao kiểm tra riêng khi diễn tập migration hoặc phục hồi dữ liệu.
4. Cài `deploy/lynveris.service` vào systemd và khởi động dịch vụ. Kiểm tra `/ready` qua loopback. `/ready` phải báo `model=ready` và `threat=configured`.
5. Dùng `deploy/Caddyfile` làm cấu hình Caddy. Đặt `LYNVERIS_PUBLIC_HOST` trong môi trường của dịch vụ Caddy. Cho phép cổng 80 và 443 của Caddy để cấp chứng chỉ. Uvicorn chỉ nghe `127.0.0.1:8000` và chỉ tin proxy header từ loopback. Caddy giới hạn kích thước body, thời gian chờ và ba đường dẫn API cần thiết cho app. Chạy `caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile` trước khi khởi động.
6. Kiểm tra từ mạng ngoài với chứng chỉ hợp lệ. Mở app HTTPS, kiểm tra một URL đối chứng, kiểm tra trạng thái từng nguồn rồi thử lỗi mạng. Chỉ phân phối khi đúng phiên bản model, tình trạng nguồn và kết quả đầu cuối đã được xác nhận.
