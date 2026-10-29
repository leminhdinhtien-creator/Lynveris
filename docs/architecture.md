# Kiến trúc và vận hành

Flutter trích URL trên thiết bị và chỉ gửi URL đã chọn đến FastAPI. Backend tách cấu trúc bằng `urllib.parse`, xử lý IDNA bằng `idna`, xác định miền đăng ký bằng PSL đã đóng gói, so sánh bằng confusables UTS #39 phiên bản 17.0.0 và danh mục thương hiệu có nguồn. Model nếu đã cấu hình dùng chung hàm đặc trưng với pipeline offline. Google Safe Browsing là adapter độc lập, được gọi chỉ khi có lựa chọn của người dùng. PostgreSQL chỉ lưu thống kê tối thiểu có đồng ý; lịch sử nằm trên thiết bị.

## Ranh giới tin cậy

- API chỉ nhận một URL HTTP/HTTPS tối đa 4.096 ký tự. Body tối đa 16 KiB, rate limit mặc định 30 request/phút/client trong một tiến trình, bộ nhớ giới hạn số client. Reverse proxy phải có giới hạn body, thời gian nhận request và tổng kết nối; đặt Uvicorn sau proxy đã cấu hình đúng, không tin tuỳ tiện `X-Forwarded-For`.
- Không truy cập hostname do người dùng cung cấp; không DNS lookup, HTTP HEAD, follow redirect, JavaScript, file download hoặc cookie của URL đích. Vì vậy địa chỉ private, metadata, IPv6 hoặc DNS rebinding không tạo đường SSRF từ tính năng này. Nếu bổ sung resolver sau này phải kiểm tra IP thật của socket và từng hop; hiện chưa có tính năng đó.
- Không cache trạng thái "an toàn". Cache provider lưu HMAC của URL với salt trong RAM; không lưu URL. Kết quả Google dương tính tuân thủ TTL, tối đa 30 phút. Lỗi/timeout/quota/thiếu cấu hình có trạng thái riêng. Không tìm thấy trong nguồn không chứng minh URL hợp lệ.
- Khoá Google chỉ ở backend; không đặt trong Dart, APK, Git hoặc tham số CLI. Adapter gọi endpoint cố định qua HTTPS, timeout, tối đa hai lần thử, đồng thời tối đa tám, cooldown quota, không theo redirect. Dịch vụ này chỉ dùng cho đề tài phi thương mại theo điều khoản đã đối chiếu.
- Danh mục chính thức là bằng chứng đối chiếu danh tính, không phải allowlist. Không bỏ qua path/query hay nguồn ngoài trên host chính thức. Thiếu thương hiệu trong danh mục không chứng minh nguy hiểm; danh mục hiện không đầy đủ.
- Skeleton dùng tailoring NFD → confusables17 → NFD trên IDNA brand labels; không sửa URL, chưa triển khai full v17 bidiSkeleton/Default_Ignorable/Script_Extensions. Bảng chữ Latin/Greek/Cyrillic dựa Unicode names của Python, không tuyên bố full UTS39 conformance. Unicode tiếng Việt và IDN không tự trở thành cảnh báo mạnh.

## Các mức kết quả

| Mức | Điều kiện và giới hạn |
|---|---|
| Nguy cơ cao | Nguồn tin có phát hiện còn hiệu lực, có nguồn và thời gian |
| Cần thận trọng | Luật giả mạo URL mạnh hoặc mô hình hợp lệ vượt ngưỡng |
| Chưa phát hiện dấu hiệu đáng ngờ | Có mô hình hoạt động, không có tín hiệu dương tính; vẫn giới hạn ở phạm vi kiểm tra |
| Chưa đủ thông tin | Thiếu mô hình và bằng chứng, hoặc thiếu đích link rút gọn, hoặc nguồn bắt buộc cho lượt kiểm tra bị lỗi |

Khi model chưa sẵn sàng, luật URL vẫn giúp nêu dấu hiệu nhưng chất lượng thống kê chưa được đo. Điểm phân loại không được hiển thị dưới dạng phần trăm xác suất lừa đảo. Không suy diễn tuổi miền, DNS hay chứng chỉ. Lịch sử và kết quả Google hết hạn được hiển thị như bản ghi cũ, yêu cầu dán lại URL gốc để kiểm tra mới.

## Riêng tư và xoá

Mặc định tắt lịch sử, tra Google và đóng góp thống kê. Clipboard chỉ đọc khi bấm Dán. Android chỉ nhận nội dung qua ACTION_SEND/PROCESS_TEXT từ thao tác chia sẻ của người dùng; không xin SMS, Contacts hoặc quyền nền. Chia sẻ kết quả dùng share sheet của hệ điều hành và chỉ kèm hostname, mức kết quả, thời gian, hướng dẫn; không gửi cả URL có token hoặc tin nhắn.

Lịch sử tối đa 100 mục/30 ngày; bỏ toàn bộ userinfo, path, query, fragment trước khi lưu. Giữ lý do, kết quả và phiên bản để xem lại. Tắt lịch sử xoá dữ liệu đang lưu. Các mục cũ được dọn lúc mở ứng dụng và khi thêm kết quả. Android tắt backup ứng dụng. Bộ nhớ thiết bị vẫn cần khoá màn hình; việc gỡ ứng dụng làm mất mã xoá thống kê, các thống kê còn lại tự hết hạn.

Đóng góp thống kê lưu UUID sự kiện, hash mã xoá ngẫu nhiên của cài đặt, mức cảnh báo, giờ, phiên bản model, trạng thái nguồn. Không lưu URL, nội dung tin nhắn hoặc IP vào bảng nghiên cứu. Đây là dữ liệu giả danh tối thiểu, không phải vô danh tuyệt đối. Hết hạn sau 7 ngày, dọn mỗi giờ và trước insert. `DELETE /v1/research` với `X-Deletion-Token` xoá thống kê của thiết bị. Mã đủ dài để tránh đoán; endpoint không nhận owner ID tuỳ ý.

Uvicorn tắt access log. Validation handler không echo đầu vào. Không ghi exception chứa URL/request key. Không bật HTTP debug logging, OpenTelemetry exporter, body capture hay proxy log query/header nhạy cảm khi triển khai. Cache provider ở RAM mất khi dừng tiến trình; thao tác xoá thống kê cũng xóa cache của tiến trình. Không lưu kết quả cá nhân trên backend.

## Cơ sở dữ liệu và triển khai

Compose dùng PostgreSQL 18, job migration Alembic chạy trước API, health check cơ sở dữ liệu và API. Không công khai cổng database. API bind cổng host 127.0.0.1; cần reverse proxy HTTPS cho điện thoại thật. Một worker phù hợp bản đề tài; rate limit/cache hiện nằm trong RAM từng tiến trình. Khi mở rộng nhiều worker, chuyển giới hạn và cache sang kho chia sẻ có kiểm soát hoặc áp rate limit tại proxy, không giả định giới hạn hiện tại là toàn cụm.

SQLite chỉ là lựa chọn phát triển nhanh; kiểm thử PostgreSQL riêng xác nhận DDL, insert và deletion. `.env.example` không chứa bí mật. Biến model rỗng tạo trạng thái `unavailable`. Muốn nạp artifact vào Docker, mount thư mục chỉ đọc tại `/models/model-v1` và đặt `LYNVERIS_MODEL_DIRECTORY` trỏ vào đó; giữ nguyên phiên bản thư viện và dữ liệu tham chiếu khớp manifest.

Trước khi công khai API: dùng HTTPS, giới hạn tại reverse proxy, khoá Google restricted phù hợp backend, mật khẩu PostgreSQL ngẫu nhiên dạng URL-safe, secret manager/env của máy chủ, bản sao DB được mã hoá và lịch xoá tương ứng. Không có endpoint quản trị trong sản phẩm.
