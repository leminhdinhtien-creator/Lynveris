# Kiểm tra sản phẩm

Ngày kiểm tra: **29/10/2026, múi giờ Việt Nam**. Chạy trực tiếp trên Windows của máy phát triển, không phải cloud/WSL. Đây là kết quả chạy phần mềm, không phải đánh giá chất lượng nhận diện trên dữ liệu thực địa. Test có AI hỗ trợ; không nhận là test do sinh viên tự viết.

## Đã xác minh tại máy phát triển

| Phạm vi | Kết quả thực tế |
|---|---|
| Backend `pytest backend/tests` | **114 passed**; gồm hồi quy chế độ giữ dữ liệu cũ và adapter OpenPhish |
| Ruff check/format | Đạt với backend và scripts |
| Flutter analyze | Không phát hiện lỗi |
| Flutter unit/widget | **15 passed**, gồm API client, chọn dữ liệu gửi, lỗi mạng, trích URL, lưu/xoá/ẩn thông tin lịch sử, lỗi lưu thiết bị, điều hướng, nhận Share khi đang xem kết quả/đang chờ API, hai lượt kiểm tra liên tiếp và cỡ chữ 150% trên màn hình nhỏ |
| Android → FastAPI → PostgreSQL thật | Ca `product_flow_test.dart` đạt trên Small_Phone/emulator-5554: URL thường trả thiếu thông tin, userinfo giả hostname trả thận trọng, một URL đang có trong feed OpenPhish trả nguy cơ cao. Collector đọc đúng ba ID phản hồi Flutter từ SQL, sau đó xác nhận việc xoá qua Flutter và bảo toàn các ID có sẵn |
| PostgreSQL 18.6 trên máy | Database `lynveris`, cổng **5432**, migration **0001_minimal_events**. Role `lynveris_app` có SELECT/INSERT/DELETE, không superuser/createdb/createrole/schema CREATE/TRUNCATE. Mật khẩu quản trị nhập tại cửa sổ local, không lưu; `.env` chứa riêng thông tin role runtime, bị gitignore và giới hạn ACL |
| Lịch sử trên Android | Lưu thật qua SharedPreferences, tạo AppStore mới đọc lại đủ ba mục, ẩn path/query, mở lại chi tiết, xoá một mục và xoá hết dữ liệu thử đều đạt |
| Mất kết nối và timeout trên Android | Thử cổng đóng và TCP nhận kết nối nhưng không phản hồi: UI báo chưa kiểm tra/quá thời gian chờ, không tạo kết quả và không lưu thêm thống kê |
| Nguồn thật | OpenPhish Community: tải HTTPS thật 300 URL, đối chiếu có/không có trong feed. Không truy cập URL phishing, không dùng transport giả ở runtime. Google thiếu khoá trả `not_configured` và kết quả thiếu thông tin |
| SQLite phát triển | Schema check không có thay đổi chưa migrate |
| APK ứng dụng thường | Build debug thành công. Bản trong `artifacts/lynveris-debug.apk` được kiểm tra không chứa entrypoint integration test; không dùng APK test runner để bàn giao |
| Docker Compose trên CI | Build image, chạy migrations/PostgreSQL/API bằng Compose, chờ healthy và gọi `/ready` đã đạt |
| GitHub CI | Cả backend và Flutter đã **success** tại commit `8a179ff9197b60b01fea483864de8b6bbc8aca86`: [run 40710865943](https://github.com/leminhdinhtien-creator/Lynveris/actions/runs/40710865943) |
| Flutter web | Build cuối thành công với `--no-web-resources-cdn`; đã kiểm tra giao diện và gọi API thật bằng trình duyệt |
| Dữ liệu thật | Collector xác nhận 235.795 dòng UCI: nhãn gốc 100.945 phishing / 134.850 legitimate. Manifest ở `data/phiusiil-quarantine/manifest.json`; không đưa vào train temporal do thiếu timestamp từng dòng |

Một cảnh báo thư viện Starlette về việc tương lai chuyển test client từ httpx sang httpx2 còn xuất hiện; hiện 109 test chạy đạt với bộ phiên bản khoá. Gradle/JDK 25 phát cảnh báo native access; build debug vẫn thành công. Không dùng các cảnh báo này làm bằng chứng ứng dụng đã chạy trên mọi thiết bị.

## Phạm vi tự động

- Phân tách scheme, userinfo, hostname, port, path, query, fragment; không thay URL gốc, không giải mã lặp; từ chối URL mơ hồ/control/numeric IP viết tắt.
- PSL nhiều cấp, private hosting như github.io/pages.dev/blogspot.com; Unicode hợp lệ, chữ Việt, Greek/Cyrillic confusables, typo/thêm bớt/đảo chữ, subdomain/userinfo giả mạo và query chứa địa chỉ khác.
- Bộ hồi quy phát triển **38 tình huống thiết kế**, không phải 38 mẫu thực địa đã được gán nhãn; cộng các ca lỗi cấu trúc và thành phần khác. Không dùng làm test nghiên cứu cuối.
- Provider tests dùng **httpx MockTransport**, kiểm tra phát hiện/không tìm thấy/thiếu cấu hình/lỗi/timeout/quota/cache và phản hồi sai định dạng. Chưa kiểm tra Google live bằng khoá thật.
- Kiểm tra SSRF theo kiến trúc không truy cập URL đích: private IP, metadata và IPv6 chỉ được phân tích, redirect luôn `not_requested`. Chưa triển khai hoặc tuyên bố resolver chống rebinding.
- Pipeline test dùng fixture tổng hợp trong thư mục tạm: provenance thiếu, timestamp tương lai, blacklist không đúng thời điểm, nhóm miền/chiến dịch liên thông, chọn ngưỡng với FPR của toàn bộ phép kết hợp, train/load/evaluate và khoá test một lần. Đây là kiểm tra vòng đời phần mềm, không có model thật từ các fixture đó trong ứng dụng.

## Lỗi đã quan sát và sửa

| Lỗi phát triển thực sự quan sát | Cách sửa và hồi quy |
|---|---|
| Rò rỉ khi hai miền nối gián tiếp qua chiến dịch ở tập sau | Union nhóm miền/campaign trước khi phân tập; test transitive aliases ban đầu thất bại, sau sửa đạt |
| Provider có cacheDuration dạng số làm phát sinh exception; NaN hoặc threatType lạ được chấp nhận | Kiểm tra kiểu, duration và danh mục trước khi tổng hợp; các trường hợp trả `error`, không biến thành an toàn/phát hiện |
| Tên Lynveris tràn khi tăng cỡ chữ ở màn hình hẹp | Giới hạn riêng wordmark theo chiều rộng, giữ chữ nội dung lớn; hồi quy cỡ chữ 150% đạt |
| Bộ trích URL loại dấu câu có thể mang nghĩa trong path/query | Giữ nguyên span URL; kiểm thử dấu `!`, `)` và dấu chấm cuối miền |
| Trạng thái tải được giữ đến lúc đóng màn hình kết quả, làm ô nhập chưa nhận nội dung khi quay về nhanh trên Android | Kết thúc trạng thái tải trước khi điều hướng; hồi quy gửi hai URL liên tiếp trên emulator và kiểm tra controller/request thật đã đạt |
| Nhận Android Share khi đang xem kết quả chỉ cập nhật ô nhập phía dưới, màn hình kết quả cũ vẫn che nội dung mới | Trở về route đầu khi nhận Share; tăng thế hệ yêu cầu để phản hồi đang chờ không đẩy kết quả cũ lên lại. Hồi quy ban đầu thất bại, sau sửa widget tests đạt |

Chưa có **10 lỗi nhận diện thực địa** được quan sát và gán nhãn. Không bịa lỗi hoặc lấy lỗi cài đặt làm số đo chất lượng phát hiện. Khi có lỗi thật, thêm bằng chứng đã ẩn thông tin vào tập phát triển và giữ tập test cuối độc lập.

## Chưa xác minh hoặc còn chặn

- **Google live:** cần `LYNVERIS_GOOGLE_API_KEY` hợp lệ ở backend và chọn provider `google`; hiện chỉ xác minh hợp đồng adapter bằng mock và trạng thái thiếu cấu hình thật. Runtime hiện dùng OpenPhish Community cho nghiên cứu, không có mock thay thế trong ứng dụng. Điều khoản OpenPhish không cho tự do phân phối lại feed hoặc sử dụng thương mại.
- **Model và H1:** cần dữ liệu hai nhãn có timestamp/bằng chứng/quyền sử dụng, đủ ba giai đoạn và snapshot blacklist đương thời. Chưa có model triển khai; chưa đo precision/recall/F1/FPR thật, URL mới, coverage nghiên cứu hoặc mức cải thiện +30 điểm phần trăm.
- **Docker tại máy này:** không có Docker CLI/daemon; chạy container đã được xác minh trên GitHub CI thay thế. PostgreSQL native cũng đã chạy đạt riêng.
- **Thiết bị thật:** đã kiểm tra emulator; chưa xác minh Android Share từ từng ứng dụng nguồn, share sheet/OEM, bàn phím và khả năng đọc trên điện thoại vật lý/người dùng gia đình. Không có thử nghiệm pilot hoặc chỉ số H2 trong phạm vi bàn giao.

## Kiểm tra thiết bị trước khi dùng rộng hơn

Trên điện thoại thử nghiệm với backend HTTPS thật: chia sẻ một URL và tin nhắn nhiều URL từ ứng dụng nguồn; xác nhận chỉ URL được chọn gửi đi; thử Dán/Xoá, bàn phím và chữ lớn; thử mất mạng/timeout; bật/tắt lịch sử, xoá từng mục/tất cả; mở share sheet rồi huỷ; xác minh thống kê bật/tắt/xoá và thông báo lỗi khi server mất kết nối. Chưa đánh dấu các thao tác chưa thực hiện là đạt. Không gửi dữ liệu nhạy cảm hoặc URL chứa OTP/token trong các ca thử.

Ảnh ở `artifacts/screenshots/` là ảnh native do ca integration test tạo với URL thử nghiệm, không phải ảnh giao diện dựng giả. Collector đọc đúng các PNG có tên cố định trong vùng tạm của chính ứng dụng debug (code_cache hoặc cache theo SDK), xác nhận chữ ký PNG rồi báo test đã thu xong trước khi Flutter gỡ APK test. Ca thu ảnh cuối cùng đã chạy đạt.
