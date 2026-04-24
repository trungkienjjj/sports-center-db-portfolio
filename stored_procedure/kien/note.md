# 📘 Tài liệu Stored Procedures - Module Quản lý (Kiên)

**Trạng thái:** Final Version (Full Option)
**Ngày cập nhật:** 07/12/2025
**Tương thích:** Database Schema mới nhất (25 bảng, có `open_time`, `booking_date`...)

---

## 🛠️ Danh sách & Logic xử lý

### 1. Quản lý Sân bãi (Court Management)
* **`sp_AddCourt` / `sp_UpdateCourt`**: 
    * Thêm/Sửa thông tin sân.
    * **Logic:** Kiểm tra ràng buộc R1304 (Nếu Status = 'Bảo trì' thì bắt buộc phải nhập ngày bảo trì). Sử dụng `THROW` để bắn lỗi chuẩn ra Backend.
* **`sp_DeleteCourt`**: 
    * **Logic:** Kiểm tra lịch sử đặt sân. Nếu đã có booking -> Chuyển trạng thái sang 'Bảo trì' (Soft Delete). Nếu chưa -> Xóa vĩnh viễn (Hard Delete).
* **`sp_GetCourtByID`**: Lấy thông tin chi tiết để đổ vào form "Chỉnh sửa sân".

### 2. Quản lý Ca trực (Shift & Assignment)
* **`sp_CreateWorkShift`**: Tạo khung giờ làm việc. Kiểm tra `StartTime < EndTime`.
* **`sp_AssignShift`**: 
    * Phân nhân viên vào ca.
    * **Logic:** Kiểm tra `RequiredCount` (Sức chứa của ca). Nếu ca đã đủ người -> Báo lỗi, không cho phân thêm.
* **`sp_GetShiftAssignmentsByDateRange`**: 
    * API hỗ trợ UI "Phân ca làm việc". Trả về danh sách ca và nhân viên đã gán để hiển thị lên lưới lịch.

### 3. Nghiệp vụ & Báo cáo (Business & Reporting)
* **`sp_ApproveLeaveRequest`**: 
    * Duyệt đơn nghỉ phép.
    * **Logic:** Nếu "Từ chối" phải có lý do (R1305). Nếu "Duyệt" phải có người thay thế.
* **`sp_CalculateSalary`**: 
    * Tính lương cuối tháng và lưu vào `salary_history`.
    * **Công thức:** (Lương cứng + Phụ cấp) - (Số ca nghỉ không phép * Phạt).
* **`sp_ReportRevenue` (Quan trọng)**: 
    * SP phức tạp nhất, trả về **5 Result Sets** cùng lúc để vẽ Dashboard:
        1.  Card tổng quan (Doanh thu, Hoàn tiền, Số hóa đơn).
        2.  Biểu đồ Line (Doanh thu theo ngày).
        3.  Biểu đồ Pie (Tỷ trọng Sân vs Dịch vụ).
        4.  **Thống kê Hủy & No-show:** Đếm số lượng, tỷ lệ hủy và ước tính thất thoát tài chính.
        5.  Bảng chi tiết theo từng Chi nhánh.

### 4. Hỗ trợ (Support)
* **`sp_GetInvoiceEmailData`**: Truy xuất dữ liệu Header, Booking và Service để Backend gửi email hóa đơn cho khách.