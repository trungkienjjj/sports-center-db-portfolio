# 🏆 Hệ thống Quản lý Trung tâm Thể thao VietSport

## 📖 Giới thiệu

Dự án **VietSport** là một hệ thống quản lý toàn diện cho các trung tâm thể thao, được phát triển bằng SQL Server. Hệ thống quản lý đầy đủ từ nhân viên, khách hàng, sân thể thao, dịch vụ, đặt sân cho đến hóa đơn và lương.

---

## 📁 Cấu trúc dự án

```
scripts-database/
├── create_db.sql                # Tạo cơ sở dữ liệu & 25 bảng
├── create_data.sql              # Chèn dữ liệu mẫu
├── create_constraints.sql       # Ràng buộc & Triggers
├── stored_procedure/            # Stored procedures (theo từng thành viên)
│   ├── hieu/
│   ├── kien/
│   ├── nguyen/
│   ├── nhan/
│   └── quan/
└── README.md
```

---

## 🗄️ Cơ sở dữ liệu

### Tên: **SportsCenterDB**

### 📊 25 Bảng dữ liệu:

#### **Phase 1: Bảng độc lập**

- `branch` - Chi nhánh/cơ sở
- `court_type` - Loại sân (Cầu Lông, Futsal, Tennis, v.v.)
- `work_shift` - Ca trực làm việc
- `role` - Vai trò người dùng
- `customer_level` - Cấp độ khách hàng (Platinum, Gold, Silver, Thường)
- `service` - Dịch vụ (Huấn luyện, Tủ đồ, Thuê dụng cụ, v.v.)

#### **Phase 2: Bảng có khóa ngoại cấp 1**

- `account` - Tài khoản (liên kết với `role`)
- `discount_policy` - Chính sách giảm giá

#### **Phase 3: Bảng có khóa ngoại cấp 2**

- `customer` - Khách hàng
- `employee` - Nhân viên
- `court` - Sân thể thao
- `branch_service` - Dịch vụ của chi nhánh

#### **Phase 4: Bảng có khóa ngoại cấp 3**

- `trainer_referee_info` - Thông tin huấn luyện viên/trọng tài
- `salary_history` - Lịch sử lương
- `leave_request` - Đơn xin nghỉ phép
- `court_booking` - Phiếu đặt sân
- `shift_assignment` - Phân công ca trực

#### **Phase 5: Bảng có khóa ngoại cấp 4**

- `maintenance_report` - Báo cáo bảo trì
- `booking_slots` - Khung giờ đặt sân
- `service_booking` - Phiếu đặt dịch vụ
- `service_booking_item` - Chi tiết dịch vụ đặt
- `invoice` - Hóa đơn
- `refund_info` - Thông tin hoàn tiền

#### **Phase 6: Bảng nối (Relationship tables)**

- `invoice_discount` - Liên kết hóa đơn & chính sách giảm giá
- `service_booking_trainer_referee` - Liên kết dịch vụ & huấn luyện viên/trọng tài

---

## 🚀 Hướng dẫn sử dụng

### 1️⃣ Tạo cơ sở dữ liệu

```sql
-- Chạy file: create_db.sql
-- Tạo database 'SportsCenterDB' và 25 bảng với 6 giai đoạn
```

### 2️⃣ Chèn dữ liệu mẫu

```sql
-- Chạy file: create_data.sql
-- Chèn dữ liệu: 3 chi nhánh, 5 vai trò, nhân viên, khách hàng, sân, dịch vụ, đơn hàng mẫu
```

### 3️⃣ Áp dụng ràng buộc và Triggers

```sql
-- Chạy file: create_constraints.sql
-- Cấu hình các rule (ràng buộc) và triggers tự động
```

---

## ✨ Tính năng chính

### 👥 Quản lý Nhân viên

- ✅ Thông tin cơ bản (Họ tên, Ngày sinh, CCCD, Địa chỉ, v.v.)
- ✅ Lương, phụ cấp, hoa hồng
- ✅ Lịch sử lương theo tháng/năm
- ✅ Phân công ca trực
- ✅ Đơn xin nghỉ phép
- ✅ Thông tin huấn luyện viên (HLV cá nhân)

### 🎫 Quản lý Khách hàng

- ✅ Thông tin cá nhân đầy đủ
- ✅ Cấp độ khách hàng (Platinum/Gold/Silver/Thường)
- ✅ Điểm thưởng (Loyalty points)
- ✅ Lịch sử đặt sân

### 🏐 Quản lý Sân thể thao

- ✅ Loại sân (Cầu Lông, Futsal, Tennis, Bóng Rổ, Bóng Đá Mini)
- ✅ Trạng thái sân (Còn trống, Đã đặt, Đang sử dụng, Bảo trì)
- ✅ Giá theo giờ
- ✅ Sức chứa
- ✅ Lịch bảo trì

### 📋 Quản lý Đặt Sân

- ✅ Đặt trực tuyến (Online) & Đặt trực tiếp (Direct)
- ✅ Trạng thái đặt (Đã thanh toán, Chưa thanh toán, Đã hủy, Đang giữ chỗ)
- ✅ Khung giờ booking (Booking slots)
- ✅ Kiểm tra trùng giờ tự động
- ✅ Phí hủy sân (Trước 24h, Trong 24h, Không tới)

### 🛎️ Quản lý Dịch vụ

- ✅ Các loại dịch vụ: Dụng cụ (Bóng, Vợt), Nhân sự (HLV, Trọng tài), Tiện ích (Tủ đồ, Phòng tắm)
- ✅ Tồn kho & ngưỡng tồn kho
- ✅ Giá đơn vị theo chi nhánh
- ✅ Quản lý bằng đơn vị (Lần, Giờ, Lượt, Tháng, v.v.)

### 💰 Quản lý Tài chính

- ✅ Hóa đơn cho sân & dịch vụ
- ✅ Hình thức thanh toán (Tiền mặt, Chuyển khoản, Thẻ, Ví điện tử)
- ✅ Chính sách giảm giá (HSSV, Khách hàng thân thiết, v.v.)
- ✅ Xử lý hoàn tiền
- ✅ Lịch sử lương & thanh toán

---

## 🔒 Các ràng buộc dữ liệu (Constraints)

### Ràng buộc Kiểu dữ liệu

| Rule  | Nội dung                                               |
| ----- | ------------------------------------------------------ |
| R1101 | Trạng thái nhân viên: `Working`, `Retired`, `On Leave` |
| R1102 | Giới tính: `Nam`, `Nữ`, `Khác`                         |
| R1103 | Lương, phụ cấp, hoa hồng ≥ 0                           |
| R1104 | Giới tính khách hàng: `Nam`, `Nữ`, `Khác`              |
| R1105 | Điểm thưởng khách hàng ≥ 0                             |

### Ràng buộc Độc nhất (Unique)

| Rule  | Nội dung                                 |
| ----- | ---------------------------------------- |
| R1202 | Mỗi nhân viên chỉ 1 bảng lương/tháng/năm |
| R1203 | Tên chi nhánh duy nhất                   |
| R1204 | Tên loại sân duy nhất                    |
| R1205 | Username tài khoản duy nhất              |
| R1206 | Tên dịch vụ duy nhất                     |

### Ràng buộc Thời gian

| Rule  | Nội dung                                         |
| ----- | ------------------------------------------------ |
| R1301 | Thời gian bắt đầu < thời gian kết thúc (Slot)    |
| R1302 | Thời gian bắt đầu < thời gian kết thúc (Ca trực) |
| R1303 | Ngày bắt đầu ≤ Ngày kết thúc (Nghỉ phép)         |

### Triggers (Quy tắc nghiệp vụ)

| Trigger      | Nội dung                                       |
| ------------ | ---------------------------------------------- |
| **TG_R1401** | Giới hạn số sân đặt online/ngày (tối đa 2 sân) |
| **TG_R1402** | Đặt online phải trước ≥ 2 giờ giờ bắt đầu      |
| **TG_R1403** | Kiểm tra sân không bị đặt trùng giờ            |
| **TG_R1404** | Kiểm tra & trừ tồn kho dịch vụ tự động         |

---

## 📊 Dữ liệu mẫu

### Chi nhánh

- 🏢 VietSport TP.HCM (Quận 10)
- 🏢 VietSport Hà Nội (Quận Cầu Giấy)
- 🏢 VietSport Cần Thơ (Quận Ninh Kiều)

### Nhân viên

- **Quản lý chi nhánh**: Nguyễn Văn A (HCM)
- **Lễ tân**: Lê Thị C
- **Kỹ thuật/HLV**: Hoàng Văn D
- **Thu ngân**: Phạm Thị E

### Khách hàng

- **Trần Thị B** - Cấp Platinum (20% giảm giá, 1000+ points)

### Sân & Dịch vụ

- Sân Cầu Lông: 150.000 VND/giờ (HCM), 140.000 VND/giờ (Cần Thơ)
- Sân Futsal: 300.000 VND/trận (HCM), 280.000 VND/trận (Cần Thơ)
- Dịch vụ: Thuê bóng, Huấn luyện viên, Tủ đồ cá nhân, v.v.

---

## 💡 Quy trình nghiệp vụ

### 1️⃣ Quy trình Đặt Sân

```
Khách → Chọn sân → Chọn thời gian → Kiểm tra trùng lịch →
Đặt Online (cần 2 giờ trước) / Đặt Trực tiếp →
Tạo hóa đơn → Thanh toán / Giữ chỗ
```

### 2️⃣ Quy trình Dịch vụ Kèm Theo

```
Khách → Chọn dịch vụ (Bóng, HLV, Tủ đồ) →
Tạo phiếu dịch vụ → Trừ tồn kho →
Tính giá → Cộng vào hóa đơn
```

### 3️⃣ Quy trình Thanh toán & Hoàn Tiền

```
Hóa đơn → Thanh toán (Tiền mặt/Chuyển khoản/Thẻ/Ví) →
Nếu hủy sân: Kiểm tra thời gian → Tính phí hủy →
Xử lý hoàn tiền
```

### 4️⃣ Quy trình Tính Lương

```
Tháng/Năm → Lương cơ bản + Phụ cấp + Hoa hồng - Phạt →
Tính lương ròng → Thanh toán → Lưu lịch sử
```

---

## 🔧 Công nghệ sử dụng

- **DBMS**: SQL Server (T-SQL)
- **Phiên bản**: 2019+ (hỗ trợ `IDENTITY`, `UNIQUEIDENTIFIER`, `TRIGGER`)
- **Loại dữ liệu**: `INT`, `DECIMAL`, `VARCHAR`, `NVARCHAR`, `DATE`, `TIME`, `DATETIME`

---

## 👥 Thành viên dự án

| Thành viên | Vị trí |
| ---------- | ------ |
| Hiệu       | -      |
| Kiên       | -      |
| Nguyên     | -      |
| Nhân       | -      |
| Quân       | -      |

---

## 📝 Ghi chú & Lưu ý

⚠️ **Trước khi chạy:**

- Đảm bảo SQL Server đang chạy
- Chạy file theo thứ tự: `create_db.sql` → `create_data.sql` → `rbtv.sql`
- Database sẽ bị xóa nếu đã tồn tại (xem dòng 11 của `create_db.sql`)

✅ **Tính năng bảo mật:**

- Username/Password lưu dưới dạng hash
- Phân quyền theo vai trò (Role-based Access Control)
- Kiểm tra ràng buộc dữ liệu tự động

✅ **Tính năng tự động hóa:**

- Trigger kiểm tra & trừ tồn kho dịch vụ
- Trigger kiểm tra trùng lịch đặt sân
- Trigger tính điểm thưởng khách hàng
- Auto-timestamp cho `created_at` các giao dịch

---

## 📞 Liên hệ & Hỗ trợ

**Repository**: DBMS-VietSport/scripts-database  
**Branch**: fix/rbtv-data  
**Ngày cập nhật**: 23/11/2025

---

**Made with ❤️ by VietSport Development Team**
