USE SportsCenterDB;
GO


-- R1101: Trạng thái của nhân viên
ALTER TABLE employee ADD CONSTRAINT CK_R1101_employee_status
CHECK ([status] IN (N'Đang làm', N'Đã nghỉ việc', N'Nghỉ phép'));
GO


-- R1102: Giới tính của Nhân viên
ALTER TABLE employee ADD CONSTRAINT CK_R1102_employee_gender
CHECK ([gender] IN (N'Nam', N'Nữ', N'Khác'));
GO


-- R1103: Lương, phụ cấp, hoa hồng phải là số không âm
ALTER TABLE employee ADD CONSTRAINT CK_R1103_employee_salary_non_negative
CHECK (base_salary >= 0 AND ISNULL(commission_rate, 0) >= 0 AND ISNULL(base_allowance, 0) >= 0);
GO


-- Ràng buộc: Các cột tiền lương trong lịch sử lương (bao gồm cả giá trị tính toán) phải là số không âm [1, 8].
ALTER TABLE salary_history ADD CONSTRAINT CK_R1103_salary_history_non_negative
CHECK (
    base_salary >= 0 AND 
    ISNULL(base_allowance, 0) >= 0 AND 
    ISNULL(commission_amount, 0) >= 0 AND 
    ISNULL(deduction_penalty, 0) >= 0 AND 
    gross_pay >= 0 AND 
    net_pay >= 0
);
GO


-- R1104: Giới tính của Khách hàng
ALTER TABLE customer ADD CONSTRAINT CK_R1104_customer_gender
CHECK ([gender] IN (N'Nam', N'Nữ', N'Khác'));
GO


-- R1105: Điểm thưởng của Khách hàng
ALTER TABLE customer ADD CONSTRAINT CK_R1105_customer_bonus_point_non_negative
CHECK (bonus_point >= 0);
GO


-- R1106: Sức chứa của Sân

-- Ràng buộc: Sức chứa của sân phải là một số nguyên dương (> 0) [2].
ALTER TABLE court ADD CONSTRAINT CK_R1106_court_capacity_positive
CHECK (capacity > 0);
GO


-- R1107: Giá sân cơ bản - Tắt để demo lỗi dirty read
-- ALTER TABLE court ADD CONSTRAINT CK_R1107_court_base_price_non_negative
-- CHECK (base_hourly_price >= 0);
-- GO


-- R1108: Trạng thái của Sân
ALTER TABLE court ADD CONSTRAINT CK_R1108_court_status_domain
CHECK ([status] IN (N'Sẵn sàng', N'Bảo trì'));
GO


-- R1109: Trạng thái của Khung giờ đặt Sân (Booking Slot)
ALTER TABLE booking_slots ADD CONSTRAINT CK_R1109_bs_status_domain
CHECK ([status] IN (N'Đã đặt', N'Đã hủy', N'Đã sử dụng'));
GO


-- R1110: Trạng thái của Phiếu đặt (Sân và Dịch vụ)

-- Cho Phiếu đặt Sân (Court Booking) (Thêm 'Đang giữ chỗ' theo dữ liệu mẫu [10])
ALTER TABLE court_booking ADD CONSTRAINT CK_R1110_cb_status_domain
CHECK ([status] IN (N'Đã thanh toán', N'Chưa thanh toán', N'Đã hủy', N'Đang giữ chỗ'));
GO


-- Cho Phiếu đặt Dịch vụ (Service Booking) (Thêm 'Đã sử dụng' theo dữ liệu mẫu [11])
ALTER TABLE service_booking ADD CONSTRAINT CK_R1110_sb_status_domain
CHECK ([status] IN (N'Đã thanh toán', N'Chưa thanh toán', N'Đã hủy'));
GO

-- Trạng thái của service_booking_item
ALTER TABLE service_booking_item ADD CONSTRAINT CK_R1110b_bs_status_domain
CHECK ([status] IN (N'Đã đặt', N'Đã hủy', N'Đã sử dụng'));
GO


-- R1111: Trạng thái Thanh toán/Xử lý

-- Trạng thái Hóa đơn: “đã thanh toán“ và “chưa thanh toán“ [4].
ALTER TABLE invoice ADD CONSTRAINT CK_R1111_invoice_status_domain
CHECK ([status] IN (N'Đã thanh toán', N'Chưa thanh toán'));
GO


-- Trạng thái Hoàn tiền: (Sử dụng giá trị thực tế trong dữ liệu mẫu [12])
ALTER TABLE refund_info ADD CONSTRAINT CK_R1111_refund_status_domain
CHECK ([status] IN (N'Đã xử lý', N'Chờ xử lý'));
GO


-- Trạng thái Thanh toán Lương: “đã thanh toán“ và “chưa thanh toán“ [4].
ALTER TABLE salary_history ADD CONSTRAINT CK_R1111_salary_status_domain
CHECK (payment_status IN (N'Đã thanh toán', N'Chưa thanh toán'));
GO


-- R1112: Hình thức Thanh toán/Hoàn tiền
ALTER TABLE invoice ADD CONSTRAINT CK_R1112_invoice_payment_method_domain
CHECK (payment_method IN (N'Tiền mặt', N'Chuyển khoản', N'Thẻ', N'Ví điện tử'));
GO


ALTER TABLE refund_info ADD CONSTRAINT CK_R1112_refund_method_domain
CHECK ([method] IN (N'Tiền mặt', N'Chuyển khoản', N'Thẻ', N'Ví điện tử'));
GO


ALTER TABLE salary_history ADD CONSTRAINT CK_R1112_salary_method_domain
CHECK (payment_method IN (N'Tiền mặt', N'Chuyển khoản', N'Thẻ', N'Ví điện tử'));
GO


-- R1113: Loại hình đặt Sân
ALTER TABLE court_booking ADD CONSTRAINT CK_R1113_cb_type_domain
CHECK ([type] IN (N'Online', N'Trực tiếp'));
GO


-- R1114: Tổng tiền trong Hóa đơn
ALTER TABLE invoice ADD CONSTRAINT CK_R1114_invoice_amount_non_negative
CHECK (total_amount >= 0);
GO


-- R1115: Trạng thái Phân công Ca trực
ALTER TABLE shift_assignment ADD CONSTRAINT CK_R1115_shift_assignment_status_domain
CHECK ([status] IN (N'Đã chấm công', N'Nghỉ có phép', N'Nghỉ không phép', N'Đã phân công'));
GO


-- R1116: Trạng thái Đơn xin Nghỉ phép
ALTER TABLE leave_request ADD CONSTRAINT CK_R1116_leave_request_status_domain
CHECK (approval_status IN (N'Chờ duyệt', N'Đã duyệt', N'Từ chối'));
GO


-- R1117: Đơn giá, tồn kho, ngưỡng tồn kho Dịch vụ Chi nhánh
ALTER TABLE branch_service ADD CONSTRAINT CK_R1117_bservice_non_negative
CHECK (unit_price >= 0 AND current_stock >= 0 AND min_stock_threshold >= 0);
GO


-- R1118: Loại hình Thuê Dịch vụ
ALTER TABLE service ADD CONSTRAINT CK_R1118_service_rental_type_domain
CHECK (rental_type IN (N'Theo giờ', N'Theo lần'));
GO

ALTER TABLE service ADD CONSTRAINT CK_R1118_service_stock_type_domain
CHECK (stock_type IN (N'theo_thoi_gian', N'tieu_hao', N'khong_gioi_han', N'hlv_trong_tai'));
GO


-- R1119: Loại hình Giảm giá
ALTER TABLE discount_policy ADD CONSTRAINT CK_R1119_discount_policy_type_domain
CHECK ([type] IN (N'co_dinh', N'phan_tram'));
GO


-- R1120: Giá trị giảm giá phải không âm
ALTER TABLE discount_policy ADD CONSTRAINT CK_R1120_discount_policy_value_non_negative
CHECK (discount_value >= 0);
GO


-- R1202: Mỗi nhân viên chỉ được có một bảng lương cho mỗi tháng/ năm
ALTER TABLE salary_history ADD CONSTRAINT UQ_R1202_employee_month_year
UNIQUE (employee_id, [month], [year]);
GO


-- R1203: Tên chi nhánh phải là duy nhất
ALTER TABLE branch ADD CONSTRAINT UQ_R1203_branch_name
UNIQUE ([name]);
GO


-- R1204: Tên loại sân phải là duy nhất

ALTER TABLE court_type ADD CONSTRAINT UQ_R1204_court_type_name
UNIQUE ([name]);
GO


-- R1205: Tên đăng nhập cho tài khoản phải là duy nhất
ALTER TABLE account ADD CONSTRAINT UQ_R1205_account_username
UNIQUE ([username]);
GO


-- R1206: Tên của mỗi loại dịch vụ là duy nhất
ALTER TABLE service ADD CONSTRAINT UQ_R1206_service_name
UNIQUE ([name]);
GO


-- R1301: Thời gian bắt đầu slot phải nhỏ hơn thời gian kết thúc
ALTER TABLE booking_slots ADD CONSTRAINT CK_R1301_slot_time_order
CHECK (start_time < end_time);
GO


-- R1302: Thời gian bắt đầu ca trực phải nhỏ hơn thời gian kết thúc
ALTER TABLE work_shift ADD CONSTRAINT CK_R1302_shift_time_order
CHECK (start_time < end_time);
GO


-- R1303: Ngày bắt đầu nghỉ phép phải nhỏ hơn hoặc bằng ngày kết thúc nghỉ phép
ALTER TABLE leave_request ADD CONSTRAINT CK_R1303_leave_date_order
CHECK (start_date <= end_date);
GO


-- R1304: Nếu sân đang bảo trì thì ngày bảo trì không được NULL
ALTER TABLE court ADD CONSTRAINT CK_R1304_maintenance_date_required
CHECK (([status] != N'Bảo trì') OR ([status] = N'Bảo trì' AND maintenance_date IS NOT NULL));
GO


-- R1305: Khi nhân viên bị 'Từ chối' nghỉ phép thì phải có lý do
ALTER TABLE leave_request ADD CONSTRAINT CK_R1305_reason_for_denial
CHECK (
    ([approval_status] != N'Từ chối') OR 
    ([approval_status] = N'Từ chối' AND reason IS NOT NULL AND DATALENGTH(reason) > 0)
);
GO


-- R1306: Khi lương được 'Đã thanh toán' thì phải có thời điểm thanh toán (paid_at)
ALTER TABLE salary_history ADD CONSTRAINT CK_R1306_paid_at_required
CHECK (
    ([payment_status] != N'Đã thanh toán') OR 
    ([payment_status] = N'Đã thanh toán' AND paid_at IS NOT NULL)
);
GO


-- R1401
CREATE TRIGGER TG_R1401_MaxCourtsPerDay
ON court_booking
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF UPDATE([type]) OR UPDATE([customer_id])
    BEGIN
        -- Lặp qua các bản ghi mới được chèn/cập nhật
        IF EXISTS (
            SELECT 1
            FROM inserted I
            JOIN branch B ON (SELECT branch_id FROM court WHERE id = I.court_id) = B.id
            WHERE I.[type] = N'Online' -- Chỉ áp dụng cho đặt online
            GROUP BY I.customer_id, CAST(I.created_at AS DATE), B.max_courts_per_day_per_user
            HAVING COUNT(I.id) > B.max_courts_per_day_per_user
        )
        BEGIN
            RAISERROR (N'Lỗi R1401: Khách hàng online không được đặt quá số sân tối đa trong một ngày.', 16, 1);
            ROLLBACK TRANSACTION;
            RETURN;
        END
    END
END
GO


-- R1402
CREATE TRIGGER TG_R1402_OnlineBookingLeadTime
ON booking_slots
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted I
        JOIN court_booking CB ON I.court_booking_id = CB.id
        WHERE CB.[type] = N'Online' -- Chỉ áp dụng cho đặt online
        -- Kiểm tra: Thời gian bắt đầu slot (start_time) PHẢI lớn hơn thời điểm tạo phiếu (created_at) + 2 giờ
        AND I.start_time <= DATEADD(HOUR, 2, CB.created_at)
        AND CAST(CB.created_at AS DATE) = CB.booking_date
    )
    BEGIN
        RAISERROR (N'Lỗi R1402: Đặt sân online phải được thực hiện trước giờ bắt đầu ít nhất 2 giờ.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END
GO


-- R1403 - Tắt để demo lỗi phantom read
-- CREATE TRIGGER TG_R1403_NoCourtOverlap
-- ON booking_slots
-- AFTER INSERT, UPDATE
-- AS
-- BEGIN
--     SET NOCOUNT ON;

--     IF EXISTS (
--         SELECT 1
--         FROM inserted AS I
--         JOIN court_booking AS CB_New 
--             ON I.court_booking_id = CB_New.id
--         JOIN booking_slots AS ExistingSlot
--             ON ExistingSlot.court_booking_id IN (
--                 SELECT id 
--                 FROM court_booking 
--                 WHERE court_id = CB_New.court_id
--                   AND booking_date = CB_New.booking_date
--             )
--             AND ExistingSlot.id != I.id
--             AND ExistingSlot.[status] IN (N'Đã đặt', N'Đang sử dụng')
--         JOIN court_booking AS CB_Old
--             ON ExistingSlot.court_booking_id = CB_Old.id
--         WHERE 
--             CB_Old.booking_date = CB_New.booking_date
--             AND I.start_time < ExistingSlot.end_time
--             AND I.end_time > ExistingSlot.start_time
--     )
--     BEGIN
--         RAISERROR (N'Lỗi R1403: Sân đã bị đặt trùng giờ trong cùng ngày.', 16, 1);
--         ROLLBACK TRANSACTION;
--         RETURN;
--     END
-- END
-- GO


-- R1404
CREATE TRIGGER TG_R1404_CheckStock
ON service_booking_item
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted I
        JOIN branch_service BS ON I.branch_service_id = BS.id
        WHERE I.quantity > BS.current_stock
    )
    BEGIN
        RAISERROR (N'Lỗi R1404: Số lượng đặt dịch vụ vượt quá tồn kho hiện tại.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END
END
GO

ALTER TABLE [holidays]
ADD CONSTRAINT CK_Holidays_OneTime_Or_Recurring CHECK (
    (
        -- one-time
        [start_date] IS NOT NULL
        AND [end_date] IS NOT NULL
        AND [rec_month] IS NULL
        AND [rec_day] IS NULL
    )
    OR (
        -- recurring
        [start_date] IS NULL
        AND [end_date] IS NULL
        AND [rec_month] IS NOT NULL
        AND [rec_day] IS NOT NULL
    )
);

ALTER TABLE [holidays]
ADD CONSTRAINT CK_Holidays_DateRange CHECK (
    [start_date] IS NULL
    OR [end_date] IS NULL
    OR [end_date] >= [start_date]
);


PRINT N'Tất cả Ràng buộc Toàn vẹn Miền Giá trị đã được thiết lập theo từng ràng buộc.';