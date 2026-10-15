# Lynveris

## 1. Thông tin đề tài

**Tên đề tài tiếng Việt:**  
Phát triển Lynveris: ứng dụng cảnh báo đường link lừa đảo trong tin nhắn cho gia đình dựa trên đặc trưng URL và nguồn tin đe doạ.

**Tên đề tài tiếng Anh:**  
Developing Lynveris: A Family App Warning of Phishing Links in Messages Based on URL Features and Threat Intelligence.

**Hình thức thực hiện:** Cá nhân, 1 sinh viên.  
**Kế thừa ĐACS:** Không kế thừa; đây là đồ án mới.

## 2. Câu định vị

Lynveris hỗ trợ thành viên gia đình, đặc biệt người lớn tuổi, kiểm tra đường link trong tin nhắn bằng đặc trưng URL kết hợp nguồn tin đe doạ, đánh giá bằng recall trên link lừa đảo mới và tỉ lệ nhận diện đúng trong bài kiểm tra trước–sau.

## 3. Trạng thái đầu W1

Đang lập đề cương và chuẩn bị minh chứng W1. Tại lần cập nhật này, repo chỉ có README; chưa có mã nguồn ứng dụng, mô hình, dữ liệu thực nghiệm hoặc kết quả pilot.

Các nội dung ở những tuần sau là **kế hoạch**, không phải tính năng đã triển khai. Không ghi số đo, kết quả kiểm thử hay xác nhận pilot khi chưa có bằng chứng thực tế.

Phạm vi theo định hướng V4 của GVHD: **URL lừa đảo trong tin nhắn**. Sản phẩm là công cụ để kiểm chứng câu hỏi nghiên cứu.

## 4. Câu hỏi nghiên cứu và giả thuyết

**CH1.** Kết hợp đặc trưng từ vựng/cấu trúc của URL với nguồn tin đe doạ có tăng recall phát hiện link lừa đảo mới so với chỉ dùng danh sách đen không?

**H1:** recall trên link lừa đảo mới (chưa có trong danh sách đen lúc thu thập) cao hơn danh sách đen ít nhất **30 điểm %**, tỉ lệ báo nhầm **≤5%**.

**CH2.** Thành viên gia đình dùng Lynveris có nhận diện đúng link lừa đảo nhiều hơn trong bài kiểm tra không?

**H2:** tỉ lệ thành viên nhận diện đúng tăng ít nhất **20 điểm %**.

CH1–CH2, H1–H2 và cách đo bắt buộc giữ theo V4; nếu cần đổi, lập ADR và trao đổi với GVHD.

## 5. Bảng trước–sau 6 cột

| Chỉ số | Cách đo | Trước | Sau | Ngày đo | Bằng chứng |
|---|---|---|---|---|---|
| Recall trên URL lừa đảo mới (%), kèm tỉ lệ báo nhầm trên URL thật | So sánh danh sách đen và mô hình kết hợp trên cùng tập kiểm thử tách theo thời gian; báo cáo TP, FP, TN, FN và phiên bản nguồn | Chưa có số đo baseline trong repo | | | |
| Tỉ lệ nhận diện đúng trong bài kiểm tra 10 tin nhắn có link (%) | Cùng thành viên gia đình; hai bộ 10 tin nhắn tương đương, cùng hướng dẫn; ghi điểm từng người trước/sau | Chưa có số đo trước trong repo | | | |

- Với CH1, “Trước” là baseline danh sách đen; “Sau” là mô hình kết hợp. Đây là so sánh hai phương pháp trong cùng điều kiện.
- Với CH2, “Trước” là tự nhận diện; “Sau” là nhận diện khi có Lynveris cảnh báo.
- Lịch dự kiến theo V4: bài kiểm tra trước W2; bộ URL W3–W4; so sánh mô hình W6; bài kiểm tra sau W8. V4 còn yêu cầu baseline sơ bộ ở W2.
- Các ô kết quả, ngày đo thực tế và bằng chứng còn trống vì chưa có dữ liệu được ghi nhận. Không dùng lịch dự kiến thay cho ngày đo thực tế.
- Cách tổng hợp chỉ số CH2 cần thống nhất với GVHD trước khi đo; không tự đổi giả thuyết.

## 6. MVP tối đa 3 Must

| Mức | Nội dung dự kiến | Mốc |
|---|---|---|
| Must #1 | Thu URL lừa đảo/thật có nhãn và nguồn; tách theo thời gian; baseline danh sách đen; bộ eval khởi đầu | W4 – 06/11/2026 |
| Must #2 | Mô hình đặc trưng URL kết hợp tra nguồn tin đe doạ; API FastAPI trả mức nguy cơ và lý do; kết nối ít nhất 1 nguồn/dịch vụ thực | W5 – 13/11/2026 |
| Must #3 | Ứng dụng Flutter dán/chia sẻ URL để kiểm tra; cảnh báo người thân; log ẩn danh | W6 – 20/11/2026 |

**Không làm trong MVP:** đọc toàn bộ tin nhắn, chặn cuộc gọi, theo dõi giao dịch ngân hàng, xử lý dữ liệu sức khoẻ. Chưa cam kết tiện ích trình duyệt hoặc chức năng ngoài 3 Must.

## 7. Nguyên lý và kế hoạch đánh giá

1. Đặc trưng URL: xem xét độ dài, cấu trúc, ký tự và dấu hiệu giống thương hiệu; đặc trưng tên miền chỉ dùng khi có dữ liệu đáng tin đúng thời điểm.
2. Nguồn tin đe doạ: lưu nguồn, thời điểm tra cứu và độ trễ cập nhật; không mặc định URL không có trong danh sách đen là an toàn.
3. Tách tập theo thời gian: giữ tập kiểm thử riêng từ đầu, không dùng để chọn đặc trưng, mô hình hoặc ngưỡng; không dùng thông tin xuất hiện sau thời điểm đánh giá.
4. Ngưỡng cảnh báo: cân bằng bỏ sót và báo nhầm; báo cả recall, precision, F1, FPR và ma trận nhầm lẫn.
5. Quyền riêng tư: chỉ nhận URL do người dùng chọn, không thu toàn bộ tin nhắn; dữ liệu pilot chỉ thu khi có đồng ý và phải được ẩn danh khi công khai.

Theo V4, W6 cần **≥10 test case, ≥5 tự động** và **eval ≥30 tình huống**, trong đó **≥10 từ lỗi thật của hệ thống**; báo tỉ lệ đạt trước/sau sửa. Bộ eval dùng phát triển phải tách khỏi tập test cuối. Đây là yêu cầu sẽ thực hiện, chưa phải kết quả hiện có.

## 8. Pilot

Dự kiến nhóm gia đình **≥8 người, có người lớn tuổi**.

Chưa có thông tin đại diện, danh sách thực tế hoặc minh chứng đồng ý được cung cấp trong repo. Cần hoàn tất xác nhận bằng văn bản và danh sách **≥2 nhóm/đơn vị dự phòng** trước CP1.

V2 yêu cầu thử 4–6 tuần; V4 đặt nhóm gia đình dùng ứng dụng ở W7 và đo sau ở W8. Cần thống nhất thời lượng với GVHD và người đại diện, không tự ghi thành thoả thuận đã có. Minh chứng công khai phải ẩn danh; không đưa thông tin riêng tư lên repo.

## 9. Công nghệ dự kiến

- Ứng dụng: Flutter / Dart.
- API và mô hình: Python / FastAPI.
- Cơ sở dữ liệu: PostgreSQL.
- Triển khai và kiểm tra: Docker / CI.
- Tích hợp: nguồn tin đe doạ / dịch vụ kiểm tra URL, sẽ chốt trong thiết kế.

Repo hiện chưa có mã nguồn để chạy. Hello World, 1 test và CI thuộc CP3 theo V4; W1 vẫn cần chuẩn bị máy có dự án chạy được khi báo cáo theo yêu cầu riêng của thầy.

## 10. Kế hoạch và việc còn thiếu ở W1

- [x] Có repo và README với tên đề tài, câu định vị, hai giả thuyết, phạm vi 3 Must và bảng trước–sau 6 cột.
- [ ] Bổ sung xác nhận pilot bằng văn bản, thông tin thực tế và ≥2 nhóm dự phòng.
- [ ] Hoàn thiện bản 1 trang: vấn đề, CH1–CH2, H1–H2, biến thay đổi và hai chỉ số.
- [ ] Hoàn thiện đề cương V2 và Phiếu đăng ký có chữ ký; gộp PDF.
- [ ] Có tài khoản AWS Academy và ảnh sau đăng nhập.
- [ ] Chuẩn bị PDF W1: Phiếu nhật ký, trả lời tư duy, Nhật ký AI, minh chứng và chương nháp.
- [ ] Chuẩn bị máy và dự án chạy được cho buổi báo cáo.

**Câu hỏi tư duy W1:** Phát biểu CH1 thành “em đổi gì, đo gì, so với cái gì (baseline/cách làm cũ)?” Trả lời 3–5 câu ở cuối Phiếu nhật ký tuần.

**Hai hạn ngày 16/10/2026 theo V4:**

- Trước **12:00**: `DACN_MSSV_HoTenKhongDau_W01.pdf`; báo cáo từ **13:30**.
- Trước **23:30**: `DACN_MSSV_HoTenKhongDau_PhieuDangKy.pdf` gồm Phiếu đăng ký đã ký + đề cương.

## 11. Lộ trình sau W1

| Tuần | Thứ Sáu | Sản phẩm cần đạt theo V4 |
|---|---|---|
| W2 | 23/10 | 5 phỏng vấn; 8 user story; MVP ≤3 Must; số trước; đọc và tóm tắt Ma 2009, Google Safe Browsing |
| W3 | 30/10 | C4, 3 ADR, ERD sơ bộ; bộ URL đợt 1; đặc tả đo; Hello World + 1 test + CI; ≥5 tài liệu |
| W4 | 06/11 | Must #1; 3 test tự viết trước AI; Chương 2 nháp; video 1–2 phút |
| W5 | 13/11 | Must #2; bảng baseline/kết hợp đợt 1; Chương 2 hoàn chỉnh; vấn đáp |
| W6 | 20/11 | Must #3; test và eval theo mục 7; ma trận nhầm lẫn, chọn ngưỡng; Chương 3 nháp |
| W7 | 27/11 | ≥2 biện pháp bảo mật; Docker + CI; 5 NFR; ≥3 góp ý thật; đóng băng tính năng; pilot; vấn đáp |
| W8 | 04/12 | Bảng trước–sau có xác nhận; chi phí 100/1.000/10.000 người; sổ tay sự cố; % hoàn thành |
| W9 | 11/12 | Báo cáo đủ 4 chương; slide 10–12 trang; thuyết trình thử 7 phút và hỏi đáp; chỉ sửa lỗi |
| W10 | 18/12 | Bản v1.0, README cuối; video 3–5 phút; báo cáo cuối ≤50 trang không kể phụ lục; Phiếu theo dõi đủ chữ ký |

**Khoá học Gói A:** Cloud Foundations – 23/10; Security Foundations – 06/11; Architecting – 50% ngày 20/11 và 100% ngày 11/12.

## 12. Quy tắc minh chứng và sử dụng AI

- Mỗi lượt dùng AI đáng kể phải được ghi vào Nhật ký AI; commit có hỗ trợ AI dùng tiền tố `[AI]`.
- Lần chỉnh README này có sử dụng AI để đối chiếu V4 và chuẩn hoá nội dung.
- Viết test trước khi nhờ AI viết code theo yêu cầu GVHD.
- Không tạo phỏng vấn, lỗi hệ thống, số đo hoặc minh chứng giả.
- Không đưa dữ liệu cá nhân pilot, mật khẩu, khoá API hoặc bí mật vào repo/công cụ AI công cộng.

