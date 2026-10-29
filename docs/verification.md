# Kiểm tra sản phẩm

Ngày kiểm tra: **29/10/2026, múi giờ Việt Nam**. Chạy trực tiếp trên Windows, không phải cloud/WSL. [Model card hiện tại](model-run-20261029.md) có benchmark thật và giới hạn; không phải pilot người dùng. Test có AI hỗ trợ; không nhận là test do sinh viên tự viết. Đã chạy lại Android với model thật và cả hai nguồn trong package QA riêng.

## Đã xác minh tại máy phát triển

| Phạm vi | Kết quả thực tế |
|---|---|
| Backend `pytest backend/tests` | **130 passed** ở lần chạy sau thêm protocol/collector/combined sources/evaluation accounting; có kiểm tra giữ dữ liệu cũ |
| Ruff check/format | Đạt với backend và scripts |
| Flutter analyze | Không phát hiện lỗi |
| Flutter unit/widget | **15 passed**, gồm API client, chọn dữ liệu gửi, lỗi mạng, trích URL, lưu/xoá/ẩn thông tin lịch sử, lỗi lưu thiết bị, điều hướng, nhận Share khi đang xem kết quả/đang chờ API, hai lượt kiểm tra liên tiếp và cỡ chữ 150% trên màn hình nhỏ |
| Android → FastAPI → PostgreSQL thật | `product_flow_test.dart` đạt với model20261029T135127Z trên Small_Phone/emulator-5554, package QA. Hai nguồn not_found, userinfo giả mạo caution, URL feed detected/high, chi tiết/model/history/save/delete đều kiểm tra thật. Collector đọc đúng ba ID từ SQL và xác nhận xóa đúng dữ liệu thử, giữ ID cũ. 10 screenshot ở `artifacts/screenshots-current/` |
| PostgreSQL 18.6 trên máy | Database `lynveris`, cổng **5432**, migration **0001_minimal_events**. Role `lynveris_app` có SELECT/INSERT/DELETE, không superuser/createdb/createrole/schema CREATE/TRUNCATE. Mật khẩu quản trị nhập tại cửa sổ local, không lưu; `.env` chứa riêng thông tin role runtime, bị gitignore và giới hạn ACL |
| Lịch sử trên Android | Lưu thật qua SharedPreferences, tạo AppStore mới đọc lại đủ ba mục, ẩn path/query, mở lại chi tiết, xoá một mục và xoá hết dữ liệu thử đều đạt |
| Mất kết nối và timeout trên Android | Thử cổng đóng và TCP nhận kết nối nhưng không phản hồi: UI báo chưa kiểm tra/quá thời gian chờ, không tạo kết quả và không lưu thêm thống kê |
| Nguồn không cấu hình trên Android | Secondary API thực có Google key rỗng và OpenPhish live: UI hiện partial và Google not_configured; không có transport/kết quả giả |
| Nguồn thật | Google key thật đã tạo/restrict API/lưu local. API provider `combined` gọi cả Google và OpenPhish; URL đối chứng not_found, URL feed detected, từng child status có thời gian thật. Có Google live detected riêng; không dùng mock runtime hoặc attribution nhầm nguồn |
| SQLite phát triển | Schema check không có thay đổi chưa migrate |
| APK ứng dụng thường | Build debug thành công. Bản trong `artifacts/lynveris-debug.apk` được kiểm tra không chứa entrypoint integration test; không dùng APK test runner để bàn giao |
| Docker Compose trên CI | Build image, chạy migrations/PostgreSQL/API bằng Compose, chờ healthy và gọi `/ready` đã đạt |
| GitHub CI | Cả backend và Flutter đã **success** tại commit `8a179ff9197b60b01fea483864de8b6bbc8aca86`: [run 40710865943](https://github.com/leminhdinhtien-creator/Lynveris/actions/runs/40710865943) |
| Flutter web | Build cuối thành công với `--no-web-resources-cdn`; đã kiểm tra giao diện và gọi API thật bằng trình duyệt |
| Dữ liệu/model thật | PhreshPhish 83.176 mẫu, temporal collection-day holdout, model thật ready trong API. Test 14.073: recall78,00%, precision95,81%, FPR5,03% (chưa đạt5%); historical TI thiếu, H1 chưa chứng minh. UCI tiếp tục cách ly |

Một cảnh báo thư viện Starlette về việc tương lai chuyển test client từ httpx sang httpx2 còn xuất hiện; hiện 109 test chạy đạt với bộ phiên bản khoá. Gradle/JDK 25 phát cảnh báo native access; build debug vẫn thành công. Không dùng các cảnh báo này làm bằng chứng ứng dụng đã chạy trên mọi thiết bị.

## Phạm vi tự động

- Phân tách scheme, userinfo, hostname, port, path, query, fragment; không thay URL gốc, không giải mã lặp; từ chối URL mơ hồ/control/numeric IP viết tắt.
- PSL nhiều cấp, private hosting như github.io/pages.dev/blogspot.com; Unicode hợp lệ, chữ Việt, Greek/Cyrillic confusables, typo/thêm bớt/đảo chữ, subdomain/userinfo giả mạo và query chứa địa chỉ khác.
- Bộ hồi quy phát triển **38 tình huống thiết kế**, không phải 38 mẫu thực địa đã được gán nhãn; cộng các ca lỗi cấu trúc và thành phần khác. Không dùng làm test nghiên cứu cuối.
- Provider unit tests dùng **httpx MockTransport** riêng, kiểm tra lỗi/timeout/quota/cache/schema; live API dùng HTTPS thật. Combined kiểm tra cả hai nguồn song song, expiry, partial failure và Google attribution đúng nguồn.
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

Lần đầu cờ QA không được truyền tới entrypoint listener do Flutter test tạo, một mục thử đã vào package chính. Đã dừng trước xóa lịch sử, khôi phục **đúng binary preferences trước test**, SHA256 trùng snapshot ban đầu, xóa đúng một row thử. Sau đó thêm prebuild/kiểm tra APK identity, nhận diện integration define và native package guard trước đọc/ghi preferences. Guard đã chặn một lượt sai package; lượt QA cuối đạt, preferences package chính vẫn cùng hash. Không reset/gỡ package chính.

URL đối chứng thiết kế `example.org` có query thử bị model cảnh báo thận trọng dù cả hai nguồn not_found; đây là false positive đối chứng, không phải lỗi thực địa được gán nhãn. Giữ model/ngưỡng khóa, không thêm whitelist hoặc sửa theo test; giới hạn mô hình thử nghiệm được hiển thị. Các URL IANA help, Wikipedia root và Microsoft Windows kiểm tra thêm trả no_signs, không dùng vài đối chứng này thay số đo test.

## Chưa xác minh hoặc còn chặn

- **Google:** đã có key thật local, không cần người dùng cung cấp thêm. Nguồn có thể lỗi/quota và được hiển thị partial; OpenPhish vẫn có giới hạn terms academic/no redistribution.
- **H1:** model đã triển khai/đo thật nhưng FPR test5,03% vượt5%, thiếu historical TI và exact label-decision timestamps. Không sửa theo test; nâng model cần test độc lập mới và thêm benign khó. Prospective collection đã bắt đầu, chưa đủ hai nhãn để xác nhận H1.
- **Docker tại máy này:** không có Docker CLI/daemon; chạy container đã được xác minh trên GitHub CI thay thế. PostgreSQL native cũng đã chạy đạt riêng.
- **Thiết bị thật:** đã kiểm tra emulator; chưa xác minh Android Share từ từng ứng dụng nguồn, share sheet/OEM, bàn phím và khả năng đọc trên điện thoại vật lý/người dùng gia đình. Không có thử nghiệm pilot hoặc chỉ số H2 trong phạm vi bàn giao.

## Kiểm tra thiết bị trước khi dùng rộng hơn

Trên điện thoại thử nghiệm với backend HTTPS thật: chia sẻ một URL và tin nhắn nhiều URL từ ứng dụng nguồn; xác nhận chỉ URL được chọn gửi đi; thử Dán/Xoá, bàn phím và chữ lớn; thử mất mạng/timeout; bật/tắt lịch sử, xoá từng mục/tất cả; mở share sheet rồi huỷ; xác minh thống kê bật/tắt/xoá và thông báo lỗi khi server mất kết nối. Chưa đánh dấu các thao tác chưa thực hiện là đạt. Không gửi dữ liệu nhạy cảm hoặc URL chứa OTP/token trong các ca thử.

Ảnh ở `artifacts/screenshots/` là ảnh native do ca integration test tạo với URL thử nghiệm, không phải ảnh giao diện dựng giả. Collector đọc đúng các PNG có tên cố định trong vùng tạm của chính ứng dụng debug (code_cache hoặc cache theo SDK), xác nhận chữ ký PNG rồi báo test đã thu xong trước khi Flutter gỡ APK test. Ca thu ảnh cuối cùng đã chạy đạt.
