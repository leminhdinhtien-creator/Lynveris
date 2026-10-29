# Bảng kiểm tra bản hiện tại

29/10/2026, Windows local, PostgreSQL 18 tại 5432, Small_Phone/emulator-5554. API thật trên 127.0.0.1:8000; Android dùng 10.0.2.2:8000. Không chạy lại benchmark khóa, không chỉnh model/threshold theo test. Đây là kiểm tra sản phẩm, không phải pilot H1/H2.

| Chức năng | Kết quả | Bằng chứng |
|---|---|---|
| Backend và migrations hiện có | Ready, không đổi schema/migration trong lượt cuối | `/ready`; migration0001_minimal_events từ lần cấu hình trước |
| Flutter → API → PostgreSQL | Đạt trên emulator, đối chiếu 3 ID và xóa đúng dữ liệu QA | `product_flow_test.dart`, local `artifacts/real-device-verification.json` |
| Model thật và hai nguồn | Model 20261029T135127Z ready; Google+OpenPhish live | Local `.verification/api-live-proof.json`; `docs/model-run-20261029.md` |
| Nhập URL, hostname thật, kết quả/chi tiết | Đạt; nguồn URL/model/TI tách rõ, không có kết luận an toàn tuyệt đối | Android product test và 10 ảnh QA local |
| Lưu/mở lại/xóa từng mục/xóa hết lịch sử | Đạt trong package QA; package chính được giữ dữ liệu | `product_flow_test.dart`, SQL collector và preservation proof local |
| Thiếu khóa nguồn | UI partial và Google not_configured, OpenPhish vẫn live | Secondary QA API thật, `lynveris-source-unavailable.png` |
| Mất kết nối/timeout | UI báo chưa kiểm tra, không tạo kết quả giả | Cổng đóng/TCP không phản hồi; ảnh offline/timeout |
| Share kết quả ra Android | Bảng Share thật mở/huỷ được; hostname/mức/thời gian, không path/query; không gửi tới người khác | Local `artifacts/screenshots-current/lynveris-android-share.png` |
| Chrome Android → Lynveris | Đạt; URL gốc hiện trong ô nhập thay vì bị kết quả cũ che | Local `lynveris-share-incoming.png` |
| Share sau khi đóng task/mở lại app | Đạt; process Android mới vẫn nhận đúng URL | Local `lynveris-share-cold-start.png`, `.verification/android-share-activity-state.txt` |
| Kiểm tra URL nhận qua Share | Đạt qua API thật; URL IANA trả no_signs có giới hạn | Local `lynveris-share-result.png` |
| Backend unit/regression | 130 passed, Ruff check/format đạt | Local `.verification/final-backend-tests.log` |
| Flutter unit/widget | 15 passed, analyze/format đạt | Local `.verification/final-flutter-tests.log` |
| APK thường | Package vn.lynveris.lynveris, main.dart, install-r thành công; không chứa test entrypoint/key pattern | Local `artifacts/lynveris-debug.apk`, `.verification/apk-content-verification.json` |
| Dữ liệu khóa | Đối chiếu 9 hash tệp model/split/report/lock, không thay đổi; ID database không thay đổi trong lượt cuối | Local `.verification/final-baseline.json` và final integrity proof |

Ảnh, log, model và dữ liệu raw là bằng chứng local, không nằm trong Git; secret không được đóng gói. Các test tổng hợp chỉ ở thư mục tạm pytest, không được dùng làm chất lượng model hoặc model triển khai.

Share được kiểm tra trực tiếp bằng giao diện Chrome Android và bảng Share của hệ điều hành, không phải giả lập callback. URL đối chứng công khai IANA; không mở trang phishing hoặc gửi nội dung cho người khác. Ảnh Recents từng gợi ý task trùng nhưng Activity Manager chưa xác nhận; không sửa launchMode/taskAffinity dựa trên nghi ngờ đó. Lượt mở lại quan sát process mới và URL vẫn đầy đủ. Manifest và model không đổi trong lượt kiểm tra cuối.

## Giới hạn còn lại

- Model nghiên cứu: test độc lập đã khóa có recall 78,00%, precision 95,81%, FPR 5,03%, **chưa đạt 5%/chưa xác nhận H1**. Giữ nguyên kết quả này.
- Không có historical TI/exact label-decision time; benchmark chỉ hồi cứu theo ngày. Prospective 300 positive chưa có negative cohort, không suy FPR/H1.
- Chưa kiểm tra điện thoại vật lý, từng app nguồn/OEM hoặc người dùng gia đình; chưa có pilot/H2. `PROCESS_TEXT` có bridge và tests phần mềm, chưa xác minh với từng ứng dụng Android nguồn.
- Benign khó/IDN/shortener/tracking chưa đủ để xác nhận chất lượng theo nhóm. Không bịa 10 lỗi nhận diện thực địa.
- APK debug cho local; chưa ký release, chưa triển khai backend HTTPS công khai. PostgreSQL không mở ra Internet. Không cần nhập lại key để chạy local.
- Docker không chạy trên máy này; CI có kiểm tra Compose/PostgreSQL riêng. Kết luận CI chỉ dựa run của đúng commit hiện tại, không lấy run cũ thay thế.
