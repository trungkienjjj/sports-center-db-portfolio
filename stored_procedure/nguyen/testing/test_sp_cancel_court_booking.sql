/*
 * =================================================================
 * TEST SCRIPT - sp_CancelCourtBooking
 * Người thực hiện : Nguyên (test)
 * Ngày            : 06/12/2025
 * Yêu cầu         :
 *   - Đã chạy: create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:  sp_CancelCourtBooking, sp_CancelServiceBooking
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: CLEANUP DỮ LIỆU TEST CŨ (NẾU CÓ)
 * ================================================================*/

PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

-- Xóa theo thứ tự FK (từ con lên cha)
-- 1. Xóa refund_info test
DELETE RI
FROM refund_info RI
JOIN invoice I ON RI.invoice_id = I.id
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43;

-- 2. Xóa invoice test (gắn với booking test qua booked_base_price marker)
DELETE I
FROM invoice I
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43;

-- 3. Xóa booking_slots test
DELETE FROM booking_slots
WHERE court_booking_id IN (
    SELECT id
    FROM court_booking
    WHERE booked_base_price = 98765.43
);

-- 4. Xóa court_booking test
DELETE FROM court_booking
WHERE booked_base_price = 98765.43;

PRINT N'=== CLEANUP DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU CHUNG
 *   - Lấy 1 khách hàng mẫu (B – phone 0902000002)
 *   - Lấy 1 sân & branch tương ứng (lấy sân đầu tiên)
 *   - Lấy loyalty_point_rate, cancel_fee_before/within_24h
 *   - Đặt lại bonus_point khách mẫu về 1 giá trị lớn để test
 * ================================================================*/

PRINT N'=== PREPARE: Lấy khách hàng, sân & chi nhánh test ===';

DECLARE
    @MainCustomerId         INT,
    @MainCustomerName       NVARCHAR(255),
    @OriginalBonusMain      INT,
    @TestBaseBonus          INT,

    @TestCourtId            INT,
    @BranchId               INT,
    @LoyaltyRateBranch      DECIMAL(5, 2),
    @CancelBefore24Percent  DECIMAL(5, 2),
    @CancelWithin24Percent  DECIMAL(5, 2);

-- Khách hàng mẫu
SELECT TOP 1
    @MainCustomerId    = id,
    @MainCustomerName  = full_name,
    @OriginalBonusMain = bonus_point
FROM customer
WHERE phone_number = '0902000002';

IF @MainCustomerId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy khách hàng mẫu (sđt 0902000002).', 16, 1);
    RETURN;
END

-- Chọn 1 sân bất kỳ + branch
SELECT TOP 1
    @TestCourtId = C.id,
    @BranchId    = C.branch_id
FROM court C
ORDER BY C.id;

IF @TestCourtId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy sân nào trong hệ thống.', 16, 1);
    RETURN;
END

-- Lấy thông tin branch
SELECT
    @LoyaltyRateBranch     = B.loyalty_point_rate,
    @CancelBefore24Percent = B.cancel_fee_before_24h_percent,
    @CancelWithin24Percent = B.cancel_fee_within_24h_percent
FROM branch B
WHERE B.id = @BranchId;

IF @LoyaltyRateBranch IS NULL SET @LoyaltyRateBranch = 0;
IF @CancelBefore24Percent IS NULL SET @CancelBefore24Percent = 0;
IF @CancelWithin24Percent IS NULL SET @CancelWithin24Percent = 0;

PRINT N'  -> Khách hàng mẫu: ' + @MainCustomerName + N' (ID = ' + CAST(@MainCustomerId AS NVARCHAR(10)) + N')';
PRINT N'  -> Court test ID : ' + CAST(@TestCourtId AS NVARCHAR(10));
PRINT N'  -> Branch ID     : ' + CAST(@BranchId AS NVARCHAR(10));
PRINT N'  -> Loyalty rate  : ' + CAST(@LoyaltyRateBranch AS NVARCHAR(20));
PRINT N'  -> Cancel <24h   : ' + CAST(@CancelBefore24Percent AS NVARCHAR(20));
PRINT N'  -> Cancel within 24h: ' + CAST(@CancelWithin24Percent AS NVARCHAR(20));
PRINT N'';

-- Đặt bonus_point test đủ lớn để không bị âm
SET @TestBaseBonus = 100000;
UPDATE customer
SET bonus_point = @TestBaseBonus
WHERE id = @MainCustomerId;

PRINT N'  -> Đặt bonus_point test cho khách = ' + CAST(@TestBaseBonus AS NVARCHAR(20));
PRINT N'';


/* ================================================================
 * PHẦN 2: TẠO CÁC BOOKING TEST KHÁC NHAU
 *   - B1: Invoice Đã thanh toán, trước 24h  (TC01 + TC08)
 *   - B2: Invoice Đã thanh toán, trong 24h (TC02)
 *   - B3: Invoice Chưa thanh toán          (TC03)
 *   - B4: Slot Đã sử dụng                  (TC04)
 *   - B5: Đã qua giờ bắt đầu               (TC05)
 *   - B6: Booking bình thường cho case Method sai (TC06)
 * ================================================================*/

PRINT N'=== PREPARE: Tạo các court_booking test ===';

DECLARE
    @NowBase                   DATETIME = GETDATE(),

    @B1_FirstSlotStart         DATETIME,
    @B1_FirstSlotEnd           DATETIME,
    @B2_FirstSlotStart         DATETIME,
    @B2_FirstSlotEnd           DATETIME,
    @B3_FirstSlotStart         DATETIME,
    @B3_FirstSlotEnd           DATETIME,
    @B4_FirstSlotStart         DATETIME,
    @B4_FirstSlotEnd           DATETIME,
    @B5_FirstSlotStart         DATETIME,
    @B5_FirstSlotEnd           DATETIME,
    @B5_CreatedAt              DATETIME,
    @B6_FirstSlotStart         DATETIME,
    @B6_FirstSlotEnd           DATETIME,
    @B6_CreatedAt              DATETIME,

    @B1_Id                     INT,
    @B2_Id                     INT,
    @B3_Id                     INT,
    @B4_Id                     INT,
    @B5_Id                     INT,
    @B6_Id                     INT,

    @B1_InvoiceId              INT,
    @B2_InvoiceId              INT,
    @B3_InvoiceId              INT,
    @B6_InvoiceId              INT,

    @InvoiceB1Amount           DECIMAL(10, 2),
    @InvoiceB2Amount           DECIMAL(10, 2),
    @InvoiceB3Amount           DECIMAL(10, 2),
    @InvoiceB6Amount           DECIMAL(10, 2);

-- Đặt thời gian slot cho từng booking
SET @B1_FirstSlotStart = DATEADD(DAY, 3,  @NowBase);                           -- > 24h
SET @B1_FirstSlotEnd   = DATEADD(HOUR, 1, @B1_FirstSlotStart);

SET @B2_FirstSlotStart = DATEADD(HOUR, 12, @NowBase);                          -- trong 24h
SET @B2_FirstSlotEnd   = DATEADD(HOUR, 1,  @B2_FirstSlotStart);

SET @B3_FirstSlotStart = DATEADD(DAY, 2,  @NowBase);                           -- > 24h, chưa thanh toán
SET @B3_FirstSlotEnd   = DATEADD(HOUR, 1, @B3_FirstSlotStart);

SET @B4_FirstSlotStart = DATEADD(DAY, 1,  @NowBase);                           -- slot Đã sử dụng
SET @B4_FirstSlotEnd   = DATEADD(HOUR, 1, @B4_FirstSlotStart);

SET @B5_FirstSlotStart = DATEADD(HOUR, -1, @NowBase);                          -- ĐÃ qua giờ
SET @B5_FirstSlotEnd   = DATEADD(HOUR,  1, @B5_FirstSlotStart);


-- B1: Đã thanh toán, trước 24h
INSERT INTO court_booking
(
    booking_date,
    [type],
    [status],
    by_month,
    booked_base_price,
    holiday_charge,
    weekend_charge,
    customer_id,
    employee_id,
    court_id,
    created_at
)
VALUES
(
    CAST(@B1_FirstSlotStart AS DATE),
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @NowBase
);
SET @B1_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B1_FirstSlotStart, @B1_FirstSlotEnd, N'Đã đặt', 0.00, @B1_Id);

SET @InvoiceB1Amount = 200000.00;
-- Lưu ý: payment_method phải là một trong: 'Tiền mặt', 'Chuyển khoản', 'Thẻ', 'Ví điện tử'
INSERT INTO invoice (total_amount, payment_method, [status], court_booking_id, employee_id)
VALUES (@InvoiceB1Amount, N'Tiền mặt', N'Đã thanh toán', @B1_Id, NULL);
SET @B1_InvoiceId = SCOPE_IDENTITY();


-- B2: Đã thanh toán, trong 24h
INSERT INTO court_booking
(
    booking_date, [type], [status], by_month, booked_base_price,
    holiday_charge, weekend_charge, customer_id, employee_id, court_id, created_at
)
VALUES
(
    CAST(@B2_FirstSlotStart AS DATE),
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @NowBase
);
SET @B2_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B2_FirstSlotStart, @B2_FirstSlotEnd, N'Đã đặt', 0.00, @B2_Id);

SET @InvoiceB2Amount = 150000.00;
INSERT INTO invoice (total_amount, payment_method, [status], court_booking_id, employee_id)
VALUES (@InvoiceB2Amount, N'Tiền mặt', N'Đã thanh toán', @B2_Id, NULL);
SET @B2_InvoiceId = SCOPE_IDENTITY();


-- B3: Chưa thanh toán (free cancel)
INSERT INTO court_booking
(
    booking_date, [type], [status], by_month, booked_base_price,
    holiday_charge, weekend_charge, customer_id, employee_id, court_id, created_at
)
VALUES
(
    CAST(@B3_FirstSlotStart AS DATE),
    N'Online',
    N'Chưa thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @NowBase
);
SET @B3_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B3_FirstSlotStart, @B3_FirstSlotEnd, N'Đã đặt', 0.00, @B3_Id);

SET @InvoiceB3Amount = 120000.00;
INSERT INTO invoice (total_amount, payment_method, [status], court_booking_id, employee_id)
VALUES (@InvoiceB3Amount, N'Tiền mặt', N'Chưa thanh toán', @B3_Id, NULL);
SET @B3_InvoiceId = SCOPE_IDENTITY();


-- B4: Có slot Đã sử dụng
INSERT INTO court_booking
(
    booking_date, [type], [status], by_month, booked_base_price,
    holiday_charge, weekend_charge, customer_id, employee_id, court_id, created_at
)
VALUES
(
    CAST(@B4_FirstSlotStart AS DATE),
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @NowBase
);
SET @B4_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B4_FirstSlotStart, @B4_FirstSlotEnd, N'Đã sử dụng', 0.00, @B4_Id);


-- B5: Đã qua giờ bắt đầu (No-show, không cho hủy)
-- Lưu ý: Trigger R1402 yêu cầu đặt sân online phải trước giờ bắt đầu ít nhất 2 giờ
-- Để không vi phạm trigger: created_at phải cách start_time ít nhất 2 giờ
-- Nhưng để test "đã qua giờ bắt đầu": GETDATE() phải >= start_time
-- Giải pháp: created_at = 3 ngày trước, start_time = 1 giờ trước @NowBase
SET @B5_CreatedAt = DATEADD(DAY, -3, @NowBase);

INSERT INTO court_booking
(
    booking_date, [type], [status], by_month, booked_base_price,
    holiday_charge, weekend_charge, customer_id, employee_id, court_id, created_at
)
VALUES
(
    CAST(@B5_FirstSlotStart AS DATE),
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @B5_CreatedAt
);
SET @B5_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B5_FirstSlotStart, @B5_FirstSlotEnd, N'Đã đặt', 0.00, @B5_Id);


-- B6: Booking bình thường để test Method sai
-- Cần có slot và invoice để khi hủy, SP sẽ tạo refund_info với @Method không hợp lệ
-- Lưu ý: Đổi sang +10 ngày để tránh trùng với B1 (+3 ngày) và không vi phạm trigger R1403
SET @B6_FirstSlotStart = DATEADD(DAY, 10, @NowBase);  -- KHÁC HẲN B1 (10 ngày thay vì 3 ngày)
SET @B6_FirstSlotEnd   = DATEADD(HOUR, 1, @B6_FirstSlotStart);
SET @B6_CreatedAt      = @NowBase;  -- > 2h trước giờ bắt đầu => không vi phạm R1402

SET @InvoiceB6Amount = 100000.00;

INSERT INTO court_booking
(
    booking_date, [type], [status], by_month, booked_base_price,
    holiday_charge, weekend_charge, customer_id, employee_id, court_id, created_at
)
VALUES
(
    CAST(@B6_FirstSlotStart AS DATE),
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @B6_CreatedAt
);
SET @B6_Id = SCOPE_IDENTITY();

INSERT INTO booking_slots (start_time, end_time, [status], night_charge, court_booking_id)
VALUES (@B6_FirstSlotStart, @B6_FirstSlotEnd, N'Đã đặt', 0.00, @B6_Id);

INSERT INTO invoice (total_amount, payment_method, [status], court_booking_id, employee_id)
VALUES (@InvoiceB6Amount, N'Tiền mặt', N'Đã thanh toán', @B6_Id, NULL);
SET @B6_InvoiceId = SCOPE_IDENTITY();

PRINT N'  -> B1 (trước 24h) Id      = ' + CAST(@B1_Id AS NVARCHAR(10));
PRINT N'  -> B2 (trong 24h) Id      = ' + CAST(@B2_Id AS NVARCHAR(10));
PRINT N'  -> B3 (chưa thanh toán) Id= ' + CAST(@B3_Id AS NVARCHAR(10));
PRINT N'  -> B4 (slot Đã sử dụng) Id= ' + CAST(@B4_Id AS NVARCHAR(10));
PRINT N'  -> B5 (đã qua giờ) Id     = ' + CAST(@B5_Id AS NVARCHAR(10));
PRINT N'  -> B6 (method sai) Id     = ' + CAST(@B6_Id AS NVARCHAR(10));
PRINT N'';


/* ================================================================
 * PHẦN 3: TEMP TABLE BẮT KẾT QUẢ SP
 * ================================================================*/

IF OBJECT_ID('tempdb..#CancelCourtResult') IS NOT NULL
    DROP TABLE #CancelCourtResult;

CREATE TABLE #CancelCourtResult
(
    CourtBookingId      INT,
    CourtInvoiceId      INT,
    CourtRefundAmount   DECIMAL(10, 2),
    ServiceRefundAmount DECIMAL(10, 2),
    TotalRefundAmount   DECIMAL(10, 2)
);


/* ================================================================
 * PHẦN 4: TEST CASES
 * ================================================================*/

PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_CancelCourtBooking';
PRINT N'============================================================';
PRINT N'';


/* ---------------------------------------------------------------
 * TC01: Hủy sân B1 - Invoice Đã thanh toán, trước 24h
 *   - Expect:
 *       + SP thành công
 *       + CourtRefundAmount = Invoice * (1 - cancel_before_24h_percent)
 *       + ServiceRefundAmount = 0 (không có dịch vụ)
 *       + TotalRefundAmount = CourtRefundAmount
 *       + court_booking.status = N'Đã hủy'
 *       + booking_slots.status = N'Đã hủy'
 *       + bonus_point giảm đúng CAST(Refund * loyalty_rate)
 * ---------------------------------------------------------------*/
PRINT N'TC01 - Hủy sân trước 24h (invoice Đã thanh toán)';

BEGIN TRY
    DECLARE
        @B1_BonusBefore          INT,
        @B1_BonusAfter           INT,
        @B1_ExpectedPenalty      DECIMAL(10, 2),
        @B1_ExpectedRefund       DECIMAL(10, 2),
        @B1_ExpectedBonusSubtract INT,
        @R1_BookingId            INT,
        @R1_InvoiceId            INT,
        @R1_CourtRefund          DECIMAL(10, 2),
        @R1_ServiceRefund        DECIMAL(10, 2),
        @R1_TotalRefund          DECIMAL(10, 2),
        @B1_Status               NVARCHAR(50),
        @SlotStatusCount         INT;

    TRUNCATE TABLE #CancelCourtResult;

    SELECT @B1_BonusBefore = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    INSERT INTO #CancelCourtResult
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B1_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC01 - Hủy trước 24h';

    IF (SELECT COUNT(*) FROM #CancelCourtResult) <> 1
        RAISERROR (N'TC01: SP không trả về đúng 1 dòng.', 16, 1);

    SELECT TOP 1
        @R1_BookingId     = CourtBookingId,
        @R1_InvoiceId     = CourtInvoiceId,
        @R1_CourtRefund   = CourtRefundAmount,
        @R1_ServiceRefund = ServiceRefundAmount,
        @R1_TotalRefund   = TotalRefundAmount
    FROM #CancelCourtResult;

    IF @R1_BookingId <> @B1_Id OR @R1_InvoiceId <> @B1_InvoiceId
        RAISERROR (N'TC01: CourtBookingId hoặc CourtInvoiceId trả về không đúng.', 16, 1);

    -- Tính expected refund
    SET @B1_ExpectedPenalty = @InvoiceB1Amount * @CancelBefore24Percent;
    IF @B1_ExpectedPenalty < 0 SET @B1_ExpectedPenalty = 0;
    IF @B1_ExpectedPenalty > @InvoiceB1Amount SET @B1_ExpectedPenalty = @InvoiceB1Amount;

    SET @B1_ExpectedRefund = @InvoiceB1Amount - @B1_ExpectedPenalty;
    IF @B1_ExpectedRefund < 0 SET @B1_ExpectedRefund = 0;

    IF @R1_CourtRefund <> @B1_ExpectedRefund
        RAISERROR (N'TC01: CourtRefundAmount không đúng theo cancel_before_24h_percent.', 16, 1);

    IF @R1_ServiceRefund <> 0
        RAISERROR (N'TC01: ServiceRefundAmount phải = 0 do không có dịch vụ.', 16, 1);

    IF @R1_TotalRefund <> @R1_CourtRefund
        RAISERROR (N'TC01: TotalRefundAmount phải = CourtRefundAmount khi không có dịch vụ.', 16, 1);

    -- Kiểm tra trạng thái booking & slots
    SELECT @B1_Status = [status]
    FROM court_booking
    WHERE id = @B1_Id;

    IF @B1_Status <> N'Đã hủy'
        RAISERROR (N'TC01: court_booking.status sau khi hủy phải là "Đã hủy".', 16, 1);

    SELECT @SlotStatusCount = COUNT(*)
    FROM booking_slots
    WHERE court_booking_id = @B1_Id
      AND [status] = N'Đã hủy';

    IF @SlotStatusCount = 0
        RAISERROR (N'TC01: Không tìm thấy booking_slots với status = "Đã hủy".', 16, 1);

    -- Kiểm tra bonus_point
    SELECT @B1_BonusAfter = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    SET @B1_ExpectedBonusSubtract = CAST(@B1_ExpectedRefund * @LoyaltyRateBranch AS INT);
    IF @B1_ExpectedBonusSubtract < 0 SET @B1_ExpectedBonusSubtract = 0;

    IF @B1_BonusAfter <> 
       CASE WHEN @B1_BonusBefore < @B1_ExpectedBonusSubtract
            THEN 0
            ELSE @B1_BonusBefore - @B1_ExpectedBonusSubtract
       END
    BEGIN
        RAISERROR (N'TC01: bonus_point khách hàng không giảm đúng theo công thức.', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC02: Hủy sân B2 - Invoice Đã thanh toán, trong 24h
 * ---------------------------------------------------------------*/
PRINT N'TC02 - Hủy sân trong 24h (invoice Đã thanh toán)';

BEGIN TRY
    DECLARE
        @B2_BonusBefore          INT,
        @B2_BonusAfter           INT,
        @B2_ExpectedPenalty      DECIMAL(10, 2),
        @B2_ExpectedRefund       DECIMAL(10, 2),
        @B2_ExpectedBonusSubtract INT,
        @R2_BookingId            INT,
        @R2_InvoiceId            INT,
        @R2_CourtRefund          DECIMAL(10, 2),
        @R2_ServiceRefund        DECIMAL(10, 2),
        @R2_TotalRefund          DECIMAL(10, 2),
        @B2_Status               NVARCHAR(50),
        @SlotStatusCount2        INT;

    TRUNCATE TABLE #CancelCourtResult;

    SELECT @B2_BonusBefore = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    INSERT INTO #CancelCourtResult
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B2_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC02 - Hủy trong 24h';

    IF (SELECT COUNT(*) FROM #CancelCourtResult) <> 1
        RAISERROR (N'TC02: SP không trả về đúng 1 dòng.', 16, 1);

    SELECT TOP 1
        @R2_BookingId     = CourtBookingId,
        @R2_InvoiceId     = CourtInvoiceId,
        @R2_CourtRefund   = CourtRefundAmount,
        @R2_ServiceRefund = ServiceRefundAmount,
        @R2_TotalRefund   = TotalRefundAmount
    FROM #CancelCourtResult;

    IF @R2_BookingId <> @B2_Id OR @R2_InvoiceId <> @B2_InvoiceId
        RAISERROR (N'TC02: CourtBookingId hoặc CourtInvoiceId trả về không đúng.', 16, 1);

    SET @B2_ExpectedPenalty = @InvoiceB2Amount * @CancelWithin24Percent;
    IF @B2_ExpectedPenalty < 0 SET @B2_ExpectedPenalty = 0;
    IF @B2_ExpectedPenalty > @InvoiceB2Amount SET @B2_ExpectedPenalty = @InvoiceB2Amount;

    SET @B2_ExpectedRefund = @InvoiceB2Amount - @B2_ExpectedPenalty;
    IF @B2_ExpectedRefund < 0 SET @B2_ExpectedRefund = 0;

    IF @R2_CourtRefund <> @B2_ExpectedRefund
        RAISERROR (N'TC02: CourtRefundAmount không đúng theo cancel_within_24h_percent.', 16, 1);

    IF @R2_ServiceRefund <> 0
        RAISERROR (N'TC02: ServiceRefundAmount phải = 0 do không có dịch vụ.', 16, 1);

    IF @R2_TotalRefund <> @R2_CourtRefund
        RAISERROR (N'TC02: TotalRefundAmount phải = CourtRefundAmount khi không có dịch vụ.', 16, 1);

    -- Trạng thái
    SELECT @B2_Status = [status]
    FROM court_booking
    WHERE id = @B2_Id;

    IF @B2_Status <> N'Đã hủy'
        RAISERROR (N'TC02: court_booking.status sau khi hủy phải là "Đã hủy".', 16, 1);

    SELECT @SlotStatusCount2 = COUNT(*)
    FROM booking_slots
    WHERE court_booking_id = @B2_Id
      AND [status] = N'Đã hủy';

    IF @SlotStatusCount2 = 0
        RAISERROR (N'TC02: Không tìm thấy booking_slots với status = "Đã hủy".', 16, 1);

    -- Bonus
    SELECT @B2_BonusAfter = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    SET @B2_ExpectedBonusSubtract = CAST(@B2_ExpectedRefund * @LoyaltyRateBranch AS INT);
    IF @B2_ExpectedBonusSubtract < 0 SET @B2_ExpectedBonusSubtract = 0;

    IF @B2_BonusAfter <> 
       CASE WHEN @B2_BonusBefore < @B2_ExpectedBonusSubtract
            THEN 0
            ELSE @B2_BonusBefore - @B2_ExpectedBonusSubtract
       END
    BEGIN
        RAISERROR (N'TC02: bonus_point khách hàng không giảm đúng theo công thức.', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC03: Hủy sân B3 - Invoice Chưa thanh toán (free cancel)
 *   - Expect:
 *       + SP thành công
 *       + CourtRefundAmount = 0
 *       + Không thay đổi bonus_point
 * ---------------------------------------------------------------*/
PRINT N'TC03 - Hủy sân với invoice Chưa thanh toán (free cancel)';

BEGIN TRY
    DECLARE
        @B3_BonusBefore    INT,
        @B3_BonusAfter     INT,
        @R3_CourtRefund    DECIMAL(10, 2),
        @R3_ServiceRefund  DECIMAL(10, 2),
        @R3_TotalRefund    DECIMAL(10, 2);

    TRUNCATE TABLE #CancelCourtResult;

    SELECT @B3_BonusBefore = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    INSERT INTO #CancelCourtResult
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B3_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC03 - Hủy chưa thanh toán';

    SELECT TOP 1
        @R3_CourtRefund   = CourtRefundAmount,
        @R3_ServiceRefund = ServiceRefundAmount,
        @R3_TotalRefund   = TotalRefundAmount
    FROM #CancelCourtResult;

    IF @R3_CourtRefund <> 0
        RAISERROR (N'TC03: CourtRefundAmount phải = 0 với invoice Chưa thanh toán.', 16, 1);

    SELECT @B3_BonusAfter = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    IF @B3_BonusAfter <> @B3_BonusBefore
        RAISERROR (N'TC03: bonus_point không được thay đổi khi invoice chưa thanh toán.', 16, 1);

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC04: B4 - Có slot Đã sử dụng -> Không cho hủy
 * ---------------------------------------------------------------*/
PRINT N'TC04 - Không cho hủy nếu có slot "Đã sử dụng"';

BEGIN TRY
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B4_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC04 - Slot Đã sử dụng';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC05: B5 - Đã qua giờ bắt đầu -> Không cho hủy
 * ---------------------------------------------------------------*/
PRINT N'TC05 - Không cho hủy nếu đã qua giờ bắt đầu slot đầu tiên';

BEGIN TRY
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B5_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC05 - Đã qua giờ';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC06: B6 - Phương thức hoàn tiền không hợp lệ
 * ---------------------------------------------------------------*/
PRINT N'TC06 - Phương thức hoàn tiền không hợp lệ';

BEGIN TRY
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B6_Id,
         @Method         = N'ABC',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC06 - Method sai';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC07: Booking không tồn tại
 * ---------------------------------------------------------------*/
PRINT N'TC07 - Booking không tồn tại';

BEGIN TRY
    DECLARE @NonExistBookingId INT;
    SELECT @NonExistBookingId = ISNULL(MAX(id), 0) + 1000 FROM court_booking;

    EXEC sp_CancelCourtBooking
         @CourtBookingId = @NonExistBookingId,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC07 - Booking không tồn tại';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC08: Hủy lại B1 (đã bị hủy ở TC01) -> phải báo lỗi "đã hủy trước đó"
 * ---------------------------------------------------------------*/
PRINT N'TC08 - Hủy lại cùng booking đã bị hủy trước đó';

BEGIN TRY
    EXEC sp_CancelCourtBooking
         @CourtBookingId = @B1_Id,
         @Method         = N'Tiền mặt',
         @Type           = N'CourtCancel',
         @Reason         = N'[TEST-SP-CANCEL-COURT] TC08 - Hủy lần 2';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


PRINT N'============================================================';
PRINT N'KẾT THÚC TEST sp_CancelCourtBooking';
PRINT N'============================================================';


/* ================================================================
 * PHẦN 5: RESTORE & CLEANUP DỮ LIỆU TEST
 * ================================================================*/

PRINT N'=== RESTORE: Khôi phục bonus_point & xóa data test ===';

-- Khôi phục bonus_point gốc cho khách hàng mẫu
IF @MainCustomerId IS NOT NULL
BEGIN
    UPDATE customer
    SET bonus_point = @OriginalBonusMain
    WHERE id = @MainCustomerId;

    PRINT N'  -> bonus_point đã khôi phục về = ' + CAST(@OriginalBonusMain AS NVARCHAR(20));
END

-- Xóa theo thứ tự FK (từ con lên cha)
-- 1. Xóa refund_info test
DELETE RI
FROM refund_info RI
JOIN invoice I ON RI.invoice_id = I.id
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43
   OR RI.[reason] LIKE N'[TEST-SP-CANCEL-COURT]%';

-- 2. Xóa invoice test
DELETE I
FROM invoice I
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43;

-- 3. Xóa booking_slots test
DELETE FROM booking_slots
WHERE court_booking_id IN (
    SELECT id FROM court_booking WHERE booked_base_price = 98765.43
);

-- 4. Xóa court_booking test
DELETE FROM court_booking
WHERE booked_base_price = 98765.43;

PRINT N'=== CLEANUP HOÀN TẤT ===';
