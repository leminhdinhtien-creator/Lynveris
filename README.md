# SafeGuard AI

## 1. Thông tin đề tài

**Tên đề tài:** Nghiên cứu và phát triển nền tảng hỗ trợ nhận diện, phòng ngừa và ứng phó lừa đảo trực tuyến đa kênh ứng dụng trí tuệ nhân tạo (SafeGuard AI).

**Sinh viên:** Lê Minh Đình Tiến  
**MSSV:** 2380602224  
**Lớp:** 23DTHC7  
**Chuyên ngành:** Công nghệ phần mềm  
**Hình thức:** Đồ án chuyên ngành - Tự đề xuất

## 2. Câu định vị

Đồ án hỗ trợ người dùng Android xử lý an toàn hơn khi gặp cuộc gọi và yêu cầu chuyển tiền đáng ngờ, đo bằng tỷ lệ chọn hành động an toàn và thời gian xác định bước xử lý.

## 3. Vấn đề cần giải quyết

Người dùng có thể gặp cuộc gọi giả danh, tin nhắn lừa đảo, yêu cầu chuyển tiền hoặc những kịch bản dụ dỗ diễn ra qua nhiều lượt trao đổi. Việc xác minh thông tin thường mất thời gian và người dùng có thể đưa ra quyết định rủi ro khi bị gây áp lực.

SafeGuard AI hướng tới hỗ trợ sàng lọc cuộc gọi Android theo dữ liệu đáng tin cậy, phân tích nội dung đáng ngờ và hướng dẫn người dùng xác minh trước khi thực hiện hành động nguy hiểm.

## 4. Hai chỉ số đánh giá trước - sau

| Chỉ số | Cách đo | Trước | Sau | Ngày đo | Bằng chứng |
|---|---|---|---|---|---|
| Tỷ lệ chọn hành động an toàn (%) | Số lựa chọn đúng / tổng lựa chọn x 100; dùng bộ tình huống tương đương | Chưa đo (W1-W2) | | 12-23/10/2026; 04-18/12/2026 | evidence/metrics/actions.csv |
| Thời gian xử lý tình huống (giây) | Bấm giờ từ lúc nhận tình huống đến khi chọn bước xử lý | Chưa đo (W1-W2) | | 12-23/10/2026; 04-18/12/2026 | evidence/metrics/time.csv |

**Lưu ý:** Hai chỉ số chưa được đo thực tế. Cột Sau được để trống theo yêu cầu đăng ký. Các đường dẫn bằng chứng là vị trí dự kiến lưu dữ liệu.

## 5. Các chức năng dự kiến

- Auto Scam Shield: Sàng lọc và chặn cuộc gọi Android theo danh sách phù hợp.
- QuickCheck AI: Kiểm tra nội dung tin nhắn, hình ảnh, URL và QR.
- Scam Journey AI: Phân tích diễn biến lừa đảo qua nhiều lượt hội thoại.
- SafePause, SafePay và VerifyFlow: Hướng dẫn phòng ngừa giao dịch rủi ro và xác minh độc lập.
- Family Guardian: Chia sẻ tình huống với người thân khi được đồng ý.
- Incident Rescue và Evidence Vault: Hướng dẫn xử lý sự cố và lưu bằng chứng.
- Web Admin và AI Quality Center: Quản trị và đánh giá chất lượng hệ thống.

## 6. Công nghệ dự kiến

- Mobile: Flutter, Dart, Kotlin và Android CallScreeningService.
- Backend: Python, FastAPI, PostgreSQL.
- AI: OCR, NLP và phân tích ngữ cảnh hội thoại.
- Quản trị: React.
- Triển khai: Docker, GitHub Actions.
- Tích hợp dự kiến: Firebase Cloud Messaging và API kiểm tra URL.

## 7. Trạng thái dự án

Đang trong giai đoạn đăng ký đề tài và chờ giảng viên hướng dẫn phê duyệt. Các chức năng trên là phạm vi thiết kế dự kiến, chưa phải tính năng đã triển khai hoặc kiểm chứng.
