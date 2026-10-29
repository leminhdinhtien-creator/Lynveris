# Dữ liệu và mô hình

Lynveris dùng cùng hàm `features()` khi train và suy luận. Đã huấn luyện/triển khai local model thật trên PhreshPhish bằng protocol ngày hồi cứu riêng; [model card và số đo đã khóa](model-run-20261029.md). H1/H2 chưa được kiểm chứng. Các hướng dẫn event-time dưới đây giữ yêu cầu timestamp nghiêm ngặt; không thay ngày tải cho ngày quan sát/gán nhãn.

## Thu thập và cơ sở gán nhãn

`python scripts/collect_sources.py data/phiusiil-quarantine` tải ZIP từ UCI, kiểm tra kích thước, đọc CSV và lưu manifest SHA256, thời điểm tải, nguồn, giấy phép, số nhãn. Script không mở bất kỳ trang nào được liệt kê trong dataset.

[PhiUSIIL của Prasad và Chandra, 2024](https://archive.ics.uci.edu/dataset/967/phiusiil+phishing+url+dataset) có giấy phép CC BY 4.0. Nhãn gốc 0 là phishing, 1 là legitimate; định dạng nội bộ Lynveris đảo lại: 1 là phishing, 0 là URL hợp lệ đã có bằng chứng. Dataset có 235.795 mẫu, nhưng không có cột thời điểm quan sát/gán nhãn theo từng URL. Vì vậy dữ liệu nằm trong khu vực cách ly, không được tự động đưa vào pipeline temporal. Ngày công bố hoặc ngày tải không thay thế timestamp từng mẫu. Các đặc trưng HTML do dataset cung cấp không dùng trong bộ phát hiện URL của Lynveris.

`python scripts/import_phishtank.py export.json data/phishing.jsonl --license-reference <tham-chiếu-điều-khoản-đã-đối-chiếu>` nhập bản export được phép sử dụng. Script giữ nguyên `submission_time`, `verification_time`, ID và hash export. Chỉ nhận nhãn đã được cộng đồng xác minh. Không tự coi việc xuất hiện trong export hiện tại là bằng chứng URL đã có trong blacklist tại thời điểm quá khứ. [Tài liệu PhishTank](https://phishtank.org/developer_info.php) định nghĩa các trường này; [trang điều khoản](https://phishtank.org/terms.php) dẫn đến điều khoản Cisco hiện hành. Không dùng phần điều khoản lưu trữ làm giấy phép hiện hành.

URL hợp lệ phải có bằng chứng cho chính URL đó: nguồn chính thức, kiểm duyệt có ghi nhận, thời điểm, điều kiện sử dụng. Không lấy "không có trong blacklist" hay "thuộc tên miền nổi tiếng" làm nhãn hợp lệ. Cần lấy đủ các nhóm login, tracking, URL dài, Unicode, khuyến mãi, hosting nhiều người dùng và rút gọn đã xác minh. Không thu URL riêng tư của người khác khi chưa có quyền.

## Định dạng JSONL

Mỗi dòng có các trường:

| Trường | Ý nghĩa |
|---|---|
| `url` | URL gốc, tối đa 4.096 ký tự |
| `label` | 1 phishing; 0 URL hợp lệ có bằng chứng |
| `observed_at` | Timestamp ISO 8601 có timezone, nguồn quan sát đáng tin |
| `label_at` | Thời điểm nhãn thực sự được xác định |
| `source`, `license`, `evidence` | Nguồn HTTPS, cơ sở sử dụng và cơ sở gán nhãn chính URL |
| `category` | Nhóm URL phục vụ phân tích lỗi |
| `campaign` | Tuỳ chọn: chiến dịch/nhóm đã xác định, không suy diễn từ test |
| `threat` | Tuỳ chọn: snapshot đương thời có `status`, `checked_at`, `source`, `snapshot_id`, `expires_at` |

Không suy ra `not_found` khi thiếu `threat`. Timestamp thiếu, tương lai, không có timezone hoặc snapshot sau `observed_at` bị từ chối. Người vận hành phải xác minh bằng chứng và giấy phép; schema không thể tự chứng thực nội dung khai báo.

`scripts/snapshot_threats.py` thu trạng thái Google hiện tại với thời gian thật, khoá từ `.env`, giới hạn tốc độ và dừng khi quota/lỗi. Snapshot mới không được ghép ngược vào URL quan sát từ trước. Hash URL trong snapshot là dữ liệu giả danh, không được coi là vô danh hoặc đưa công khai. Dữ liệu nghiên cứu ngoại tuyến và raw export phải được kiểm soát truy cập và xoá theo thời hạn riêng; chúng bị gitignore.

## Tách tập và huấn luyện

Chạy từ thư mục repository, sau khi cài backend:

```powershell
lynveris-data data/reviewed.jsonl data/splits-v1 --validation-start 2026-10-01T00:00:00Z --test-start 2026-10-15T00:00:00Z
lynveris-train data/splits-v1 artifacts/model-v1
lynveris-evaluate data/splits-v1 artifacts/model-v1 artifacts/test-v1.json
```

Các ngày trên chỉ minh hoạ cú pháp. Chọn mốc theo dữ liệu thật và khoá trước khi đánh giá; không thay timestamp để khớp ví dụ. Lệnh dừng nếu không đủ dữ liệu. Mặc định mỗi tập train/validation/test cần tối thiểu 50 URL độc lập của mỗi nhãn; đây chỉ là sàn chạy phần mềm, không phải cỡ mẫu đảm bảo độ tin cậy thống kê.

Pipeline khử trùng URL nguyên bản giống hệt, chỉ nhóm gần trùng bằng hostname/path đã thay ID số và tên tham số; giữ nguyên URL nguồn. Các miền đăng ký (PSL gồm private suffix), chiến dịch và endpoint gần trùng được nối thành thành phần liên thông trước khi tách. Mỗi nhóm chỉ xuất hiện trong tập thời gian sớm nhất; các hàng chồng lấn ở tập sau bị loại và đếm trong audit. Đây là phép kiểm tra bảo thủ, vẫn có thể bỏ sót chiến dịch chưa được nhận dạng. Không giải mã/chuẩn hoá lại URL dùng để truy cập.

Nhãn được biết sau mốc train hoặc validation không dùng ở tập trước mốc đó. `train` chỉ đọc train và validation, xác minh hash/các mốc, thử Logistic Regression và HistGradientBoosting, chọn mô hình cùng ngưỡng trên validation. Không refit bằng validation sau khi chọn ngưỡng. Chính sách dương tính cuối cùng là: **Nguy cơ cao hoặc Cần thận trọng**, tương ứng phát hiện từ nguồn ngoài, luật URL mạnh hoặc điểm mô hình vượt ngưỡng. FPR của phép kết hợp này phải ≤5% trên validation; nếu luật hoặc nguồn làm vượt mức thì training từ chối xuất artifact. Không có nút bí mật để dùng test sửa ngưỡng.

`manifest.json` lưu hash model, phiên bản sklearn, feature, policy, PSL, Unicode, danh mục thương hiệu, hash tập dữ liệu, ngưỡng và các kết quả validation của hai ứng viên. Backend từ chối model không tương thích. Chỉ load joblib do người vận hành tin cậy tạo tại máy; pickle/joblib không phải định dạng an toàn cho upload tuỳ ý.

`evaluate` xác minh tập test đã khoá và tạo khoá đánh giá một lần theo artifact. Báo TP/FP/TN/FN, precision, recall, F1, FPR, coverage, tỉ lệ không kết luận, từng nhóm URL, baseline blacklist-only, URL-only và kết hợp. Trường hợp không kết luận vẫn nằm trong mẫu số. URL "mới" phải là phishing có snapshot `not_found` đúng thời điểm; nguồn thiếu/lỗi không được thay bằng vắng mặt. Không có snapshot đủ phủ thì không xác nhận H1. Khoá một lần giúp truy vết thao tác thông thường, không ngăn được người có quyền sửa trực tiếp file.

## Các phần cần dữ liệu thật

- Có hai nhãn cho benchmark ngày hồi cứu; chưa có exact label-decision timestamps cho đánh giá triển khai lịch sử nghiêm ngặt.
- Chưa có snapshot blacklist lịch sử để đánh giá khả năng phát hiện URL mới.
- Bộ hồi quy thiết kế tách khỏi test cuối. Các lỗi thực sự quan sát trong phát triển được thêm vào test có tên; chưa có 10 lỗi nhận diện thực địa, không tạo cho đủ số lượng.
- Kiểm thử vòng đời training dùng dữ liệu tổng hợp trong thư mục tạm pytest. Artifact/điểm của kiểm thử đó không được đóng gói vào ứng dụng hoặc coi là model thật.
