# Đóng băng phạm vi tính năng W07

Ngày chốt 25/11/2026. Tag `v0.9` là mốc đóng băng phạm vi đồ án theo yêu cầu
W07, không đổi ngược số phiên bản gói Android 1.2.0. Bản phát hành mang tên
Lynveris W07 Feature Freeze. Các thay đổi sau mốc này giới hạn ở sửa lỗi,
bảo mật, đo kiểm và tài liệu trong phạm vi đã chốt.

## Danh sách chốt

1. Pipeline dữ liệu có nhãn, tách theo thời gian, model URL và benchmark đã khóa.
2. API phân tích URL, Unicode và giả mạo tên miền; kết hợp model, Google Safe
   Browsing và OpenPhish khi người dùng chọn tra nguồn.
3. Flutter nhận/dán URL, chọn một URL từ tin nhắn, xem lý do, cấu trúc URL,
   trạng thái từng nguồn và giới hạn; chia sẻ bản tóm tắt qua Android.
4. Lịch sử trên thiết bị với URL đã lược thông tin riêng; lưu/xóa từng mục.
5. Thống kê tối thiểu có đồng ý, mã sở hữu và xóa theo mã; không lưu URL/tin nhắn.
6. Cài đặt kết nối và quyền riêng tư; xử lý lỗi mạng, timeout và nguồn chưa sẵn sàng.

## Chất lượng tại mốc chốt

Giao diện phiếu kết quả và radar là hoàn thiện các luồng đã có. Không thêm nguồn,
resolver, chatbot, tài khoản hoặc tính năng nghiệp vụ mới. Giữ nguyên 9 tệp
model/dữ liệu/kết quả nghiên cứu đã khóa; không đổi ngưỡng theo các ca eval.

Kết quả bảo mật, NFR, Docker và UX được ghi trong trang minh chứng W07. Model
còn cảnh báo nhầm/bỏ sót; H1/H2 chưa được xác nhận. Chưa có backend công khai,
thử nghiệm người dùng gia đình diện rộng hoặc bảo đảm nhận diện tuyệt đối.
