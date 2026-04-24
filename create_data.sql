--- INSERT DỮ LIỆU MẪU CHO HỆ THỐNG VIETSPORT
USE SportsCenterDB;
GO

-- KHAI BÁO CÁC BIẾN CẦN THIẾT ĐỂ LƯU TRỮ IDs
--------------------------------------------------
-- Biến UUID (uniqueidentifier) cho Tài khoản
DECLARE @AdminAccID uniqueidentifier;
DECLARE @ManagerHCMAccID uniqueidentifier;
DECLARE @ManagerCTAccID uniqueidentifier;
DECLARE @RecHCMAccID uniqueidentifier;
DECLARE @TechHCMAccID uniqueidentifier;
DECLARE @CashHCMAccID uniqueidentifier;
DECLARE @CustomerAccID uniqueidentifier;

-- Biến INT cho Role, Branch, Court Type, Service, Level
DECLARE @AdminRoleID INT;
DECLARE @ManagerRoleID INT;
DECLARE @ReceptionistRoleID INT;
DECLARE @TechnicalRoleID INT;
DECLARE @CashierRoleID INT;
DECLARE @CustomerRoleID INT;
DECLARE @TrainerRoleID INT;

DECLARE @BranchHCM INT;
DECLARE @BranchHN INT;
DECLARE @BranchCT INT;

DECLARE @LevelPlatinum INT;

DECLARE @BadmintonTypeID INT;
DECLARE @FutsalTypeID INT;

DECLARE @ServiceBall INT;
DECLARE @ServiceLocker INT;
DECLARE @ServiceRevive INT;

-- Biến INT cho Data ban đầu
DECLARE @CustomerID INT;
DECLARE @ManagerHCMID INT;
DECLARE @RecHCMID INT;
DECLARE @CashHCMID INT;
DECLARE @CourtHCMID INT;
DECLARE @BookingHCMID INT;
DECLARE @BookingCTID INT;
DECLARE @TechHCMID INT;
DECLARE @Shift1ID INT;
DECLARE @Shift2ID INT;
DECLARE @ServiceBallHCMBSID INT;
DECLARE @DiscountPolicyStudent INT;
DECLARE @ServiceBookingID INT;
DECLARE @ServiceBookingItemID INT;
DECLARE @InvoiceServiceID INT;

-- =================================================================
-- 1. PHASE 1: INSERT DỮ LIỆU CÁC BẢNG ĐỘC LẬP
-- =================================================================

-- 1.1. Bảng [role]
INSERT INTO [role] ([name]) VALUES
(N'Quản lý'), (N'Lễ tân'), (N'Kỹ thuật'), (N'Thu ngân'), (N'Khách hàng/Member'), (N'Quản trị hệ thống'), (N'Huấn luyện viên');

-- Lưu trữ Role IDs
SET @AdminRoleID = (SELECT id FROM [role] WHERE [name] = N'Quản trị hệ thống');
SET @ManagerRoleID = (SELECT id FROM [role] WHERE [name] = N'Quản lý');
SET @ReceptionistRoleID = (SELECT id FROM [role] WHERE [name] = N'Lễ tân');
SET @TechnicalRoleID = (SELECT id FROM [role] WHERE [name] = N'Kỹ thuật');
SET @CashierRoleID = (SELECT id FROM [role] WHERE [name] = N'Thu ngân');
SET @CustomerRoleID = (SELECT id FROM [role] WHERE [name] = N'Khách hàng/Member');
SET @TrainerRoleID = (SELECT id FROM [role] WHERE [name] = N'Huấn luyện viên');

-- 1.2. Bảng [customer_level]
INSERT INTO [customer_level] ([name], [discount_rate], [minimum_point]) VALUES
(N'Platinum', 0.20, 1000), -- Giảm 20%
(N'Gold', 0.10, 500), -- Giảm 10%
(N'Silver', 0.05, 100), -- Giảm 5%
(N'Thường', 0.00, 0);

SET @LevelPlatinum = (SELECT id FROM [customer_level] WHERE [name] = N'Platinum');

-- 1.3. Bảng [court_type]
INSERT INTO [court_type] ([name], [rent_duration]) VALUES
(N'Sân Cầu Lông', 60), -- Thuê theo giờ
(N'Sân Bóng Rổ', 60), -- Thuê theo giờ
(N'Sân Tennis', 120), -- Thuê theo ca 2 giờ
(N'Sân Bóng Đá Mini', 90), -- Thuê theo trận (90 phút)
(N'Sân Futsal', 90);

SET @BadmintonTypeID = (SELECT id FROM [court_type] WHERE [name] = N'Sân Cầu Lông');
SET @FutsalTypeID = (SELECT id FROM [court_type] WHERE [name] = N'Sân Futsal');

-- 1.4. Bảng [branch] (HCM, HN, Cần Thơ)
INSERT INTO [branch] ([name], [address], [hotline], [late_time_limit], [max_courts_per_day_per_user], [shift_pay], [shift_absence_penalty], [loyalty_point_rate], [cancel_fee_before_24h_percent], [cancel_fee_within_24h_percent], [no_show_fee_percent], [night_booking_additional_charge], [holiday_booking_additional_charge], [weekend_booking_additional_charge], [open_time], [close_time]) VALUES
(N'VietSport TP.HCM', N'Quận 10, TP.HCM', '0901234567', 15, 2, 100000, 50000, 0.05, 0.10, 0.50, 1.00, 0.05, 0.1, 0.1, '09:00', '22:00'),
(N'VietSport Hà Nội', N'Quận Cầu Giấy, Hà Nội', '0249876543', 15, 2, 110000, 60000, 0.05, 0.10, 0.50, 1.00, 0.05, 0.1, 0.1, '09:00', '22:00'),
(N'VietSport Cần Thơ', N'Quận Ninh Kiều, Cần Thơ', '0123456788', 15, 2, 110000, 60000, 0.05, 0.10, 0.50, 1.00, 0.05, 0.1, 0.1, '09:00', '22:00');

-- Lưu trữ Branch IDs
SET @BranchHCM = (SELECT id FROM [branch] WHERE [name] = N'VietSport TP.HCM');
SET @BranchHN = (SELECT id FROM [branch] WHERE [name] = N'VietSport Hà Nội');
SET @BranchCT = (SELECT id FROM [branch] WHERE [name] = N'VietSport Cần Thơ');

-- 1.5. Bảng [service] (Bao gồm dụng cụ, nhân sự, tiện ích)
INSERT INTO [service] ([name], [unit], [rental_type], [stock_type]) VALUES
(N'Thuê Bóng Đá', N'Cái', N'Theo lần', N'theo_thoi_gian'),
(N'Thuê Vợt Cầu Lông', N'Cái', N'Theo giờ', N'theo_thoi_gian'),
(N'Huấn Luyện Viên Cá Nhân', N'Người', N'Theo giờ', N'hlv_trong_tai'),
(N'Phòng Tắm VIP', N'Phòng', N'Theo lần', N'khong_gioi_han'),
(N'Tủ Đồ Cá Nhân', N'Cái', N'Theo giờ', N'theo_thoi_gian'),
(N'Nước Revive', N'Chai', N'Theo lần', N'tieu_hao'),
(N'Thuê Trọng Tài', N'Người', N'Theo giờ', N'hlv_trong_tai');

SET @ServiceBall = (SELECT id FROM [service] WHERE [name] = N'Thuê Bóng Đá');
SET @ServiceLocker = (SELECT id FROM [service] WHERE [name] = N'Tủ Đồ Cá Nhân');
SET @ServiceRevive = (SELECT id FROM [service] WHERE [name] = N'Nước Revive');

-- 1.6. Bảng [work_shift]
INSERT INTO [work_shift] ([date], [start_time], [end_time], [required_count]) VALUES
('2024-05-20', '07:00:00', '15:00:00', 3),
('2024-05-20', '14:00:00', '22:00:00', 4);

-- =================================================================
-- 2. PHASE 2: TẠO DỮ LIỆU TÀI KHOẢN
-- =================================================================

-- 2.1. Tài khoản Quản trị hệ thống
INSERT INTO [account] ([username], [password], [role_id]) VALUES
('system_admin', '$2b$10$N.6yIDCs1snYiLSQ2L8RDOqPNth1o5rAKzhFk.UACJ/a6Y0eIa0ri', @AdminRoleID); -- Password: admin_123
SET @AdminAccID = (SELECT id FROM [account] WHERE [username] = 'system_admin');

-- 2.2. Tài khoản Quản lý chi nhánh
INSERT INTO [account] ([username], [password], [role_id]) VALUES
('manager.hcm', '$2b$10$QQicqqXzl.dCs4M2KietyeZe.ft5qDCOplQeyerVc9mMX/JTHYnHS', @ManagerRoleID), -- Password: manager_hcm
('manager.ct', '$2b$10$brw..t0gKZnuzdlorNvfwOTgdUnxNfT5Uh/5QBjuOEEkDVoo93Dau', @ManagerRoleID); -- Password: manager_ct
SET @ManagerHCMAccID = (SELECT id FROM [account] WHERE [username] = 'manager.hcm');
SET @ManagerCTAccID = (SELECT id FROM [account] WHERE [username] = 'manager.ct');

-- 2.3. Tài khoản Nhân viên (Lễ tân, Kỹ thuật, Thu ngân)
INSERT INTO [account] ([username], [password], [role_id]) VALUES
('receptionist.hcm', '$2b$10$hEV2qwgxC6FCoBVsxrHfmO83wN5idue9i837HqH5D8QJDk043fSqy', @ReceptionistRoleID), -- Password: receptionist
('technical.hcm', '$2b$10$nCMoY4WY.ZNDy0P8x0rLNO42fpDzwOdLBCjnEYFftdEsox/rf1GIa', @TechnicalRoleID), -- Password: technical
('cashier.hcm', '$2b$10$DxBpKUB4kCtVZegoTr6rQOOb9QqLWj/gSNylteOsfWykYbl6XJqlm', @CashierRoleID); -- Password: cashier
SET @RecHCMAccID = (SELECT id FROM [account] WHERE [username] = 'receptionist.hcm');
SET @TechHCMAccID = (SELECT id FROM [account] WHERE [username] = 'technical.hcm');
SET @CashHCMAccID = (SELECT id FROM [account] WHERE [username] = 'cashier.hcm');

-- 2.4. Tài khoản Khách hàng
INSERT INTO [account] ([username], [password], [role_id]) VALUES
('customer.a', '$2b$10$UYrqs2CiySWJ88x1GOvEmO/ea/x0bGzIYvHriWYGLnQsOQlagxFQm', @CustomerRoleID); -- Password: customer_a
SET @CustomerAccID = (SELECT id FROM [account] WHERE [username] = 'customer.a');

-- =================================================================
-- 3. PHASE 3: TẠO DỮ LIỆU PHỤ THUỘC (EMPLOYEE, CUSTOMER, COURT)
-- =================================================================

-- 3.1. Bảng [employee]
INSERT INTO [employee] ([full_name], [gender], [dob], [id_card_number], [address], [phone_number], [email], [status], [commission_rate], [base_salary], [base_allowance], [branch_id], [user_id]) VALUES
-- HCM Staff
(N'Nguyễn Văn A (QL)', N'Nam', '1990-01-01', '001090000001', N'123 Đường A', '0901000001', 'a.nguyen@vietsport.com', N'Đang làm', 0.00, 15000000.00, 2000000.00, @BranchHCM, @ManagerHCMAccID),
(N'Lê Thị C (LT)', N'Nữ', '1998-03-20', '003098000003', N'789 Đường C', '0903000003', 'c.le@vietsport.com', N'Đang làm', 0.05, 8000000.00, 500000.00, @BranchHCM, @RecHCMAccID),
(N'Hoàng Văn D (KT)', N'Nam', '1995-12-05', '004095000004', N'101 Đường D', '0904000004', 'd.hoang@vietsport.com', N'Đang làm', 0.00, 9500000.00, 1000000.00, @BranchHCM, @TechHCMAccID),
(N'Phạm Thị E (TN)', N'Nữ', '1999-07-10', '005099000005', N'112 Đường E', '0905000005', 'e.pham@vietsport.com', N'Đang làm', 0.03, 8500000.00, 500000.00, @BranchHCM, @CashHCMAccID),
-- Cần Thơ Staff
(N'Trần Văn F (QL)', N'Nam', '1992-11-20', '006092000006', N'123 Đường F, Cần Thơ', '0906000006', 'f.tran@vietsport.com', N'Đang làm', 0.00, 14000000.00, 1800000.00, @BranchCT, @ManagerCTAccID);

SET @ManagerHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Nguyễn Văn A (QL)');
SET @RecHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Lê Thị C (LT)');
SET @CashHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Phạm Thị E (TN)');
SET @ManagerHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Nguyễn Văn A (QL)');
SET @RecHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Lê Thị C (LT)');
SET @CashHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Phạm Thị E (TN)');
SET @TechHCMID = (SELECT id FROM [employee] WHERE [full_name] = N'Hoàng Văn D (KT)');

-- 3.2. Bảng [customer]
INSERT INTO [customer] ([full_name], [dob], [gender], [id_card_number], [address], [phone_number], [email], [customer_level_id], [user_id]) VALUES
(N'Trần Thị B', '1995-05-15', N'Nữ', '002095000002', N'456 Đường B', '0902000002', 'b.tran@gmail.com', @LevelPlatinum, @CustomerAccID),
(N'Nguyễn Trần L', '2005-05-15', N'Nam', '002095000008', N'111 Đường H', '0902000020', 'b.nguyen@gmail.com', @LevelPlatinum, @CustomerAccID);

SET @CustomerID = (SELECT id FROM [customer] WHERE [phone_number] = '0902000002');

-- 3.3. Bảng [court]
INSERT INTO [court] ([status], [capacity], [base_hourly_price], [maintenance_date], [branch_id], [court_type_id], [name]) VALUES
-- Sân HCM
(N'Sẵn sàng', 4, 150000.00, '2025-10-30', @BranchHCM, @BadmintonTypeID, N'Cầu Lông HCM 1'), -- Cầu Lông HCM 1
(N'Bảo trì', 10, 300000.00, '2025-11-01', @BranchHCM, @FutsalTypeID, N'Futsal HCM 1'), -- Futsal HCM 1
-- Sân Cần Thơ
(N'Sẵn sàng', 4, 140000.00, '2025-10-30', @BranchCT, @BadmintonTypeID, N'Cầu Lông CT 1'), -- Cầu Lông CT 1
(N'Sẵn sàng', 10, 280000.00, '2025-10-30', @BranchCT, @FutsalTypeID, N'Futsal CT 1'); -- Futsal CT 1

SET @CourtHCMID = (SELECT id FROM [court] WHERE [court_type_id] = @BadmintonTypeID AND [branch_id] = @BranchHCM);

-- 3.4. Bảng [branch_service]
INSERT INTO [branch_service] ([unit_price], [current_stock], [min_stock_threshold], [status], [branch_id], [service_id]) VALUES
(20000.00, 50, 10, N'Còn', @BranchHCM, @ServiceBall), -- Thuê bóng đá HCM
(150000.00, 20, 5, N'Còn', @BranchHCM, @ServiceLocker), -- Tủ đồ cá nhân HCM
(15000.00, 5, 5, N'Hết', @BranchCT, @ServiceBall), -- Thuê bóng đá CT
(130000.00, 30, 5, N'Còn', @BranchCT, @ServiceLocker), -- Tủ đồ cá nhân CT
(20000.00, 50, 10, N'Còn', @BranchHCM, @ServiceRevive); -- Nước Revive HCM

SET @ServiceBallHCMBSID = (SELECT id FROM [branch_service] WHERE [branch_id] = @BranchHCM AND [service_id] = @ServiceBall); -- Lưu ID dịch vụ bóng đá HCM

-- 3.5. Bảng [discount_policy]
INSERT INTO [discount_policy] ([name], [type], [discount_value], [description], [branch_id]) VALUES
(N'Giảm giá Học sinh/Sinh viên', N'phan_tram', 0.10, N'Giảm 10% khi xuất trình thẻ HSSV hợp lệ.', @BranchHCM);

SET @DiscountPolicyStudent = SCOPE_IDENTITY();

-- 3.6. Bảng [work_shift] IDs
SET @Shift1ID = (SELECT id FROM [work_shift] WHERE [start_time] = '07:00:00' AND [date] = '2024-05-20');
SET @Shift2ID = (SELECT id FROM [work_shift] WHERE [start_time] = '14:00:00' AND [date] = '2024-05-20');

-- 3.7. Bảng [shift_assignment] (Phân công ca trực)
INSERT INTO [shift_assignment] ([employee_id], [work_shift_id], [status], [note]) VALUES
(@RecHCMID, @Shift1ID, N'Đã phân công', N'Ca trực lễ tân sáng'),
(@CashHCMID, @Shift1ID, N'Đã phân công', N'Ca trực thu ngân sáng'),
(@ManagerHCMID, @Shift2ID, N'Đã phân công', N'Ca trực Quản lý');

-- 3.8. Bảng [trainer_referee_info] (Huấn luyện viên)
-- Khách hàng có thể thuê huấn luyện viên cá nhân, HLV có hồ sơ chuyên môn
INSERT INTO [trainer_referee_info] ([employee_id], [num_of_exp], [university], [specialization], [price_per_hour], [sport_type], [role]) VALUES
(@TechHCMID, 5, N'Đại học TDTT', N'Bóng đá (Futsal)', 350000.00, N'Futsal', N'Huấn luyện viên');

-- 3.9. Bảng [maintenance_report] (Bảo trì sân)
INSERT INTO [maintenance_report] ([work_description], [cost], [material_used], [post_maintenance_status], [repairer_id], [court_id]) VALUES
(N'Thay lưới và sơn lại vạch sân', 2500000.00, N'Lưới mới, sơn chịu nhiệt', N'Sẵn sàng', @TechHCMID, @CourtHCMID);

-- =================================================================
-- 4. PHASE 4: TẠO DỮ LIỆU GIAO DỊCH (BOOKING & INVOICE)
-- =================================================================

-- 4.1. Đặt sân mẫu 1 (HCM - Đã thanh toán online) 
INSERT INTO [court_booking] ([type], [status], [by_month], [booked_base_price], [holiday_charge], [weekend_charge], [customer_id], [employee_id], [court_id], [booking_date], [created_at]) VALUES
(N'Online', N'Đã thanh toán', 0, 150000.00, 0.00, 0.00, @CustomerID, NULL, @CourtHCMID, '2024-05-21', '2024-05-20 16:00:00');

SET @BookingHCMID = SCOPE_IDENTITY();

-- Thêm slots cho Booking HCM (1 tiếng Cầu lông)
INSERT INTO [booking_slots] ([start_time], [end_time], [status], [night_charge], [court_booking_id]) VALUES
('2024-05-21 16:00:00', '2024-05-21 17:00:00', N'Đã đặt', 0.00, @BookingHCMID);

-- Tạo hóa đơn cho Booking HCM
INSERT INTO [invoice] ([total_amount], [payment_method], [status], [court_booking_id], [employee_id]) VALUES
(150000.00 * (1 - 0.20), N'Ví điện tử', N'Đã thanh toán', @BookingHCMID, NULL);

-- 4.3. Bảng [service_booking]
-- Tạo Phiếu đặt dịch vụ kèm theo cho Phiếu đặt sân HCM (@BookingHCMID)
INSERT INTO [service_booking] ([status], [court_booking_id], [employee_id]) VALUES
(N'Đã thanh toán', @BookingHCMID, NULL);

SET @ServiceBookingID = SCOPE_IDENTITY();

-- 4.4. Bảng [service_booking_item]
-- Khách thuê 2 quả bóng (Dụng cụ có tồn kho) 
INSERT INTO [service_booking_item] ([quantity], [start_time], [end_time], [by_month], [status], [booked_unit_price], [service_booking_id], [branch_service_id]) VALUES
(2, '2024-05-21 16:00:00', '2024-05-21 17:00:00', 0, N'Đã đặt', 20000.00, @ServiceBookingID, @ServiceBallHCMBSID);

SET @ServiceBookingItemID = SCOPE_IDENTITY();

-- 4.5. Bảng [service_booking_trainer_referee]
INSERT INTO [service_booking_trainer_referee] ([service_booking_item_id], [employee_id], [booked_price]) VALUES
(@ServiceBookingItemID, @TechHCMID, 250000.00);

-- 4.6. Tạo Hóa đơn riêng cho DỊCH VỤ
DECLARE @ServiceAmount DECIMAL(10, 2) = (SELECT unit_price FROM [branch_service] WHERE id = @ServiceBallHCMBSID) * 2; 

INSERT INTO [invoice] ([total_amount], [payment_method], [status], [service_booking_id], [employee_id]) VALUES
(@ServiceAmount, N'Tiền mặt', N'Đã thanh toán', @ServiceBookingID, @CashHCMID);

SET @InvoiceServiceID = SCOPE_IDENTITY();

-- 4.7. Áp dụng Chính sách giảm giá HSSV vào Hóa đơn Dịch vụ 
INSERT INTO [invoice_discount] ([invoice_id], [discount_policy_id]) VALUES
(@InvoiceServiceID, @DiscountPolicyStudent);

-- 4.8. Đặt sân mẫu 2 (Cần Thơ - Đặt trực tiếp, chưa thanh toán)
DECLARE @CourtCTFutsalID INT = (SELECT id FROM [court] WHERE [court_type_id] = @FutsalTypeID AND [branch_id] = @BranchCT);

INSERT INTO [court_booking] ([type], [status], [by_month], [booked_base_price], [holiday_charge], [weekend_charge], [customer_id], [employee_id], [court_id], [booking_date], [created_at]) VALUES
(N'Trực tiếp', N'Chưa thanh toán', 0, 280000.00, 0.00, 0.00, @CustomerID, @RecHCMID, @CourtCTFutsalID, '2024-05-22', '2024-05-21 19:30:00');

SET @BookingCTID = SCOPE_IDENTITY();

-- Thêm slots cho Booking Cần Thơ (90 phút Futsal)
INSERT INTO [booking_slots] ([start_time], [end_time], [status], [night_charge], [court_booking_id]) VALUES
('2024-05-22 19:30:00', '2024-05-22 21:00:00', N'Đã đặt', 0.05, @BookingCTID);

-- 4.9. Bảng [refund_info]
DECLARE @InvoiceBookingHCMID INT;
SET @InvoiceBookingHCMID = (SELECT id FROM [invoice] WHERE [court_booking_id] = @BookingHCMID);

-- 2. Tạo yêu cầu hoàn tiền cho hóa đơn đặt sân HCM
-- Giả định Khách hàng B hủy sân trước 24h (Bị phạt 10% giá gốc 150k = 15k).
-- Số tiền hoàn lại: 120,000 VND (đã trả) - 15,000 VND (phạt) = 105,000 VND.
INSERT INTO [refund_info] ([amount], [reason], [type], [method], [status], [invoice_id]) VALUES
(105000.00, N'Hủy sân trước 24 giờ (Áp dụng phí phạt 10% giá trị gốc)', N'Hủy sân', N'Chuyển khoản', N'Đã xử lý', @InvoiceBookingHCMID);


-- 4.10. Bảng [salary_history]
INSERT INTO [salary_history] ([year], [month], [base_salary], [base_allowance], [commission_rate], [commission_amount], [deduction_penalty], [gross_pay], [net_pay], [payment_status], [payment_method], [paid_at], [employee_id]) VALUES 
(2024, 4, 8000000.00, 500000.00, 0.05, 1200000.00, 50000.00, 9700000.00, 9650000.00, N'Đã thanh toán', N'Chuyển khoản', '2024-05-05 09:30:00', @RecHCMID);

-- 4.11. Bảng [leave_request]
-- Đơn xin nghỉ phép đã phê duyệt
INSERT INTO [leave_request] ([start_date], [end_date], [approval_status], [reason], [creator_id], [approver_id], [replacer_id]) VALUES 
('2024-06-10', '2024-06-12', N'Đã duyệt', N'Nghỉ phép thường niên (Du lịch gia đình)', @CashHCMID, @ManagerHCMID, @RecHCMID);

-- Đơn nghỉ phép đang chờ duyệt
INSERT INTO [leave_request] ([start_date], [end_date], [approval_status], [reason], [creator_id]) VALUES 
('2024-08-01', '2024-08-01', N'Chờ duyệt', N'Khám sức khỏe định kỳ', @TechHCMID);


-- New Year (Tết Dương Lịch)
INSERT INTO holidays (name, rec_day, rec_month) VALUES 
    (N'Tết Dương Lịch', 1, 1),
    (N'Ngày Giải Phóng Miền Nam', 30, 4),
    (N'Ngày Quốc Tế Thiếu Nhi', 1, 6),
    (N'Ngày Quốc Tế Lao Động', 1, 5),
    (N'Quốc Khánh Việt Nam', 2, 9);

INSERT INTO holidays (name, start_date, end_date) VALUES 
    (N'Tết Nguyên Đán 2025', '2025-01-28', '2025-02-02'),
    (N'Tết Nguyên Đán 2026', '2026-02-16', '2026-02-22');


PRINT 'INSERT DATA COMPLETED';

GO


