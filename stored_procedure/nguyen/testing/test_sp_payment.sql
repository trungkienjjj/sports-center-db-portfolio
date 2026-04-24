/*
 * =================================================================================
 * TEST STORED PROCEDURE: sp_Payment
 * Người thực hiện: Nguyên (test)
 * Ngày: (tự điền)
 * Mục tiêu:
 *   - Kiểm tra các rule:
 *       + Invoice phải tồn tại & status = N'Chưa thanh toán'
 *       + PaymentMethod hợp lệ
 *       + EmployeeId (nếu có) phải tồn tại
 *       + Invoice phải gắn với court_booking hoặc service_booking
 *       + Thanh toán thành công:
 *           * Cập nhật invoice.status = N'Đã thanh toán'
 *           * Cập nhật court_booking / service_booking.status = N'Đã thanh toán' (nếu chưa hủy)
 *           * Gọi sp_AddBonusPointForInvoice để cộng điểm
 *   - Các case test chính:
 *       TC01: PaymentMethod không hợp lệ  → lỗi
 *       TC02: EmployeeId không tồn tại   → lỗi
 *       TC03: InvoiceId không tồn tại    → lỗi
 *       TC04: Invoice đã thanh toán      → lỗi
 *       TC05: Thanh toán invoice sân (court_booking) thành công
 *       TC06: Thanh toán lại invoice sân đã thanh toán → lỗi
 *       TC07: Thanh toán invoice dịch vụ (service_booking) thành công
 *       TC08: Thanh toán lại invoice dịch vụ đã thanh toán → lỗi
 * =================================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

PRINT '========================================================';
PRINT 'TEST SCRIPT - sp_Payment';
PRINT '========================================================';

------------------------------------------------------------
-- 0. KHAI BÁO BIẾN & DỌN DẸP DỮ LIỆU TEST CŨ
------------------------------------------------------------
DECLARE 
    @TestBasePrice              DECIMAL(10, 2) = 777777.77, -- marker cho court_booking test
    @TestCourtId                INT,
    @TestBranchId               INT,
    @TestCustomerId             INT,
    @TestEmployeeId             INT,
    @BranchLoyaltyRate          DECIMAL(5, 2),
    @OriginalBonus              INT;

PRINT N'--- 0. Dọn dẹp dữ liệu test cũ (nếu có) ---';

-- Xóa invoice test (link tới các court_booking có booked_base_price = @TestBasePrice)
DELETE I
FROM invoice I
WHERE I.court_booking_id IN (
        SELECT CB.id 
        FROM court_booking CB 
        WHERE CB.booked_base_price = @TestBasePrice
    )
   OR I.service_booking_id IN (
        SELECT SB.id
        FROM service_booking SB
        JOIN court_booking CB ON SB.court_booking_id = CB.id
        WHERE CB.booked_base_price = @TestBasePrice
    );

-- Xóa service_booking test
DELETE SB
FROM service_booking SB
JOIN court_booking CB ON SB.court_booking_id = CB.id
WHERE CB.booked_base_price = @TestBasePrice;

-- Xóa court_booking test (booking_slots sẽ bị xóa nhờ ON DELETE CASCADE)
DELETE FROM court_booking
WHERE booked_base_price = @TestBasePrice;

------------------------------------------------------------
-- 1. LẤY DỮ LIỆU MẪU (CUSTOMER, COURT, BRANCH, EMPLOYEE)
------------------------------------------------------------
PRINT N'--- 1. Chuẩn bị dữ liệu mẫu (customer, court, branch, employee) ---';

-- 1.1. Khách hàng test (ưu tiên Trần Thị B - 0902000002 nếu có)
SELECT @TestCustomerId = id
FROM customer
WHERE phone_number = '0902000002';

IF @TestCustomerId IS NULL
BEGIN
    SELECT TOP 1 @TestCustomerId = id FROM customer ORDER BY id;
END

IF @TestCustomerId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy khách hàng mẫu để test (bảng customer trống).', 16, 1);
    RETURN;
END

-- Lưu điểm gốc để lát cuối restore
SELECT @OriginalBonus = bonus_point
FROM customer
WHERE id = @TestCustomerId;

IF @OriginalBonus IS NULL SET @OriginalBonus = 0;

-- 1.2. Chọn một sân bất kỳ + chi nhánh tương ứng
SELECT TOP 1 
    @TestCourtId  = c.id,
    @TestBranchId = c.branch_id
FROM court c
ORDER BY c.id;

IF @TestCourtId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy sân mẫu để test (bảng court trống).', 16, 1);
    RETURN;
END

SELECT @BranchLoyaltyRate = loyalty_point_rate
FROM branch
WHERE id = @TestBranchId;

IF @BranchLoyaltyRate IS NULL
BEGIN
    RAISERROR (N'Không lấy được loyalty_point_rate cho chi nhánh test.', 16, 1);
    RETURN;
END

-- 1.3. Lấy 1 nhân viên bất kỳ làm thu ngân
SELECT TOP 1 @TestEmployeeId = id
FROM employee
ORDER BY id;

IF @TestEmployeeId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy nhân viên mẫu để test (bảng employee trống).', 16, 1);
    RETURN;
END

PRINT N'   -> CustomerId = ' + CAST(@TestCustomerId AS NVARCHAR(20));
PRINT N'   -> CourtId    = ' + CAST(@TestCourtId    AS NVARCHAR(20));
PRINT N'   -> BranchId   = ' + CAST(@TestBranchId   AS NVARCHAR(20));
PRINT N'   -> EmployeeId = ' + CAST(@TestEmployeeId AS NVARCHAR(20));
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- 2. TẠO DỮ LIỆU TEST: COURT_BOOKING, SERVICE_BOOKING, INVOICE
------------------------------------------------------------
PRINT N'--- 2. Tạo dữ liệu test (court_booking, service_booking, invoice) ---';

DECLARE
    @Today                     DATE = CAST(GETDATE() AS DATE),
    @CourtBookingCourt         INT,
    @CourtBookingService       INT,
    @CourtBookingPaid          INT,
    @ServiceBookingId          INT,
    @InvoiceCourtPendingId     INT,
    @InvoiceServicePendingId   INT,
    @InvoiceAlreadyPaidId      INT,
    @AmountCourt               DECIMAL(10, 2) = 100000.00,
    @AmountService             DECIMAL(10, 2) = 50000.00;

-- 2.1. Court_booking dành cho hóa đơn sân (pending)
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
    court_id
)
VALUES
(
    DATEADD(DAY, 1, @Today),      -- ngày chơi: ngày mai
    N'Online',
    N'Chưa thanh toán',
    0,
    @TestBasePrice,               -- marker test
    0,
    0,
    @TestCustomerId,
    NULL,
    @TestCourtId
);

SET @CourtBookingCourt = SCOPE_IDENTITY();

-- Invoice pending cho court_booking
INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    employee_id,
    service_booking_id,
    court_booking_id
)
VALUES
(
    @AmountCourt,
    N'Tiền mặt',                 -- value hợp lệ theo R1112
    N'Chưa thanh toán',
    NULL,
    NULL,
    @CourtBookingCourt
);

SET @InvoiceCourtPendingId = SCOPE_IDENTITY();

-- 2.2. Court_booking + service_booking dành cho hóa đơn dịch vụ (pending)
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
    court_id
)
VALUES
(
    DATEADD(DAY, 2, @Today),
    N'Online',
    N'Chưa thanh toán',
    0,
    @TestBasePrice,
    0,
    0,
    @TestCustomerId,
    NULL,
    @TestCourtId
);

SET @CourtBookingService = SCOPE_IDENTITY();

-- service_booking pending
INSERT INTO service_booking
(
    [status],
    court_booking_id,
    employee_id
)
VALUES
(
    N'Chưa thanh toán',
    @CourtBookingService,
    NULL
);

SET @ServiceBookingId = SCOPE_IDENTITY();

-- Invoice pending cho service_booking
INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    employee_id,
    service_booking_id,
    court_booking_id
)
VALUES
(
    @AmountService,
    N'Tiền mặt',
    N'Chưa thanh toán',
    NULL,
    @ServiceBookingId,
    NULL
);

SET @InvoiceServicePendingId = SCOPE_IDENTITY();

-- 2.3. Court_booking + invoice đã thanh toán sẵn (dùng test "Đã thanh toán")
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
    court_id
)
VALUES
(
    DATEADD(DAY, 3, @Today),
    N'Online',
    N'Đã thanh toán',            -- trạng thái hiện tại không quan trọng cho test
    0,
    @TestBasePrice,
    0,
    0,
    @TestCustomerId,
    NULL,
    @TestCourtId
);

SET @CourtBookingPaid = SCOPE_IDENTITY();

INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    employee_id,
    service_booking_id,
    court_booking_id
)
VALUES
(
    75000.00,
    N'Tiền mặt',
    N'Đã thanh toán',            -- đã thanh toán từ trước
    NULL,
    NULL,
    @CourtBookingPaid
);

SET @InvoiceAlreadyPaidId = SCOPE_IDENTITY();

PRINT N'   -> InvoiceCourtPendingId   = ' + CAST(@InvoiceCourtPendingId   AS NVARCHAR(20));
PRINT N'   -> InvoiceServicePendingId = ' + CAST(@InvoiceServicePendingId AS NVARCHAR(20));
PRINT N'   -> InvoiceAlreadyPaidId    = ' + CAST(@InvoiceAlreadyPaidId    AS NVARCHAR(20));
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- 3. TEMP TABLE HỨNG KẾT QUẢ sp_Payment
------------------------------------------------------------
IF OBJECT_ID('tempdb..#PaymentResult') IS NOT NULL
    DROP TABLE #PaymentResult;

CREATE TABLE #PaymentResult
(
    InvoiceId        INT,
    InvoiceAmount    DECIMAL(10, 2),
    PaymentMethod    NVARCHAR(50),
    CustomerId       INT,
    CustomerName     NVARCHAR(255),
    BonusPointBefore INT,
    BonusPointAfter  INT,
    CourtBookingId   INT,
    ServiceBookingId INT
);

DECLARE
    @BonusBefore     INT,
    @BonusAfter      INT,
    @ExpectedAdded   INT,
    @ExpectedAfter   INT;

------------------------------------------------------------
-- TC01: PaymentMethod không hợp lệ → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC01: PaymentMethod không hợp lệ → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    EXEC sp_Payment
        @InvoiceId     = @InvoiceCourtPendingId,
        @PaymentMethod = N'ABC-KHONG-HOP-LE',
        @EmployeeId    = NULL;

    PRINT N'--> [FAIL] TC01: sp_Payment không báo lỗi với PaymentMethod không hợp lệ.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC01: Lỗi như mong đợi: ' + ERROR_MESSAGE();

    DECLARE @Status01 NVARCHAR(50);
    SELECT @Status01 = [status]
    FROM invoice
    WHERE id = @InvoiceCourtPendingId;

    IF @Status01 <> N'Chưa thanh toán'
        PRINT N'     [WARN] TC01: Trạng thái invoice đã thay đổi ngoài ý muốn.';
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC02: EmployeeId không tồn tại → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC02: EmployeeId không tồn tại → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    DECLARE @FakeEmployeeId INT = -999;

    EXEC sp_Payment
        @InvoiceId     = @InvoiceServicePendingId,
        @PaymentMethod = N'Tiền mặt',
        @EmployeeId    = @FakeEmployeeId;

    PRINT N'--> [FAIL] TC02: sp_Payment không báo lỗi khi EmployeeId không tồn tại.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC02: Lỗi như mong đợi: ' + ERROR_MESSAGE();

    DECLARE @Status02 NVARCHAR(50);
    SELECT @Status02 = [status]
    FROM invoice
    WHERE id = @InvoiceServicePendingId;

    IF @Status02 <> N'Chưa thanh toán'
        PRINT N'     [WARN] TC02: Trạng thái invoice đã thay đổi ngoài ý muốn.';
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC03: InvoiceId không tồn tại → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC03: InvoiceId không tồn tại → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    EXEC sp_Payment
        @InvoiceId     = -1,
        @PaymentMethod = N'Tiền mặt',
        @EmployeeId    = NULL;

    PRINT N'--> [FAIL] TC03: sp_Payment không báo lỗi với InvoiceId không tồn tại.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC03: Lỗi như mong đợi: ' + ERROR_MESSAGE();
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC04: Invoice đã ở trạng thái "Đã thanh toán" → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC04: Invoice đã thanh toán trước đó → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    EXEC sp_Payment
        @InvoiceId     = @InvoiceAlreadyPaidId,
        @PaymentMethod = N'Tiền mặt',
        @EmployeeId    = NULL;

    PRINT N'--> [FAIL] TC04: sp_Payment vẫn cho thanh toán invoice đã thanh toán.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC04: Lỗi như mong đợi: ' + ERROR_MESSAGE();
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC05: Thanh toán hóa đơn SÂN (court_booking) thành công
------------------------------------------------------------
PRINT N'*** TC05: Thanh toán hóa đơn sân thành công ***';

BEGIN TRY
    -- Lấy điểm hiện tại trước khi thanh toán
    SELECT @BonusBefore = bonus_point
    FROM customer
    WHERE id = @TestCustomerId;

    IF @BonusBefore IS NULL SET @BonusBefore = 0;

    SET @ExpectedAdded = CAST(@AmountCourt * @BranchLoyaltyRate AS INT);
    SET @ExpectedAfter = @BonusBefore + @ExpectedAdded;

    -- Gọi sp_Payment KHÔNG dùng INSERT-EXEC để tránh lỗi ROLLBACK trong INSERT-EXEC
    -- Lưu ý: Nếu có lỗi thực sự trong sp_Payment, sẽ hiện ra error message gốc
    EXEC sp_Payment
        @InvoiceId     = @InvoiceCourtPendingId,
        @PaymentMethod = N'Tiền mặt',
        @EmployeeId    = @TestEmployeeId;

    -- Kiểm tra invoice trên DB
    DECLARE 
        @DbInvoiceStatus   NVARCHAR(50),
        @DbPaymentMethod   NVARCHAR(50),
        @DbInvoiceEmpId    INT;

    SELECT
        @DbInvoiceStatus = [status],
        @DbPaymentMethod = payment_method,
        @DbInvoiceEmpId  = employee_id
    FROM invoice
    WHERE id = @InvoiceCourtPendingId;

    IF @DbInvoiceStatus <> N'Đã thanh toán'
        RAISERROR (N'TC05: Invoice.status không được cập nhật thành "Đã thanh toán".', 16, 1);

    IF @DbPaymentMethod <> N'Tiền mặt'
        RAISERROR (N'TC05: Invoice.payment_method không đúng.', 16, 1);

    IF @DbInvoiceEmpId <> @TestEmployeeId
        RAISERROR (N'TC05: Invoice.employee_id không đúng.', 16, 1);

    -- Kiểm tra court_booking.status
    DECLARE @DbCourtStatus NVARCHAR(50);
    SELECT @DbCourtStatus = [status]
    FROM court_booking
    WHERE id = @CourtBookingCourt;

    IF @DbCourtStatus <> N'Đã thanh toán'
        RAISERROR (N'TC05: court_booking.status không được cập nhật thành "Đã thanh toán".', 16, 1);

    -- Kiểm tra bonus_point
    DECLARE @DbCustomerBonus INT;
    SELECT @DbCustomerBonus = bonus_point
    FROM customer
    WHERE id = @TestCustomerId;

    IF @DbCustomerBonus <> @ExpectedAfter
        RAISERROR (N'TC05: Điểm thưởng sau khi cộng không đúng theo công thức (rate * amount). Expected: %d, Actual: %d', 16, 1, @ExpectedAfter, @DbCustomerBonus);

    PRINT N'--> [PASS] TC05: Thanh toán hóa đơn sân thành công, trạng thái & điểm thưởng đúng.';
END TRY
BEGIN CATCH
    PRINT N'--> [FAIL] TC05: ' + ERROR_MESSAGE();
    -- In thêm thông tin debug nếu có
    DECLARE @DebugStatus NVARCHAR(50);
    SELECT @DebugStatus = [status] FROM invoice WHERE id = @InvoiceCourtPendingId;
    PRINT N'     [DEBUG] Invoice status hiện tại: ' + ISNULL(@DebugStatus, N'NULL');
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC06: Thanh toán lại cùng hóa đơn sân → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC06: Thanh toán lại hóa đơn sân đã thanh toán → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    EXEC sp_Payment
        @InvoiceId     = @InvoiceCourtPendingId,
        @PaymentMethod = N'Tiền mặt',
        @EmployeeId    = @TestEmployeeId;

    PRINT N'--> [FAIL] TC06: sp_Payment vẫn cho thanh toán lại hóa đơn sân.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC06: Lỗi như mong đợi: ' + ERROR_MESSAGE();
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC07: Thanh toán hóa đơn DỊCH VỤ (service_booking) thành công
------------------------------------------------------------
PRINT N'*** TC07: Thanh toán hóa đơn dịch vụ thành công ***';

BEGIN TRY
    -- Lấy điểm trước khi thanh toán
    SELECT @BonusBefore = bonus_point
    FROM customer
    WHERE id = @TestCustomerId;

    IF @BonusBefore IS NULL SET @BonusBefore = 0;

    SET @ExpectedAdded = CAST(@AmountService * @BranchLoyaltyRate AS INT);
    SET @ExpectedAfter = @BonusBefore + @ExpectedAdded;

    -- Gọi sp_Payment KHÔNG dùng INSERT-EXEC để tránh lỗi ROLLBACK trong INSERT-EXEC
    -- Lưu ý: Nếu có lỗi thực sự trong sp_Payment, sẽ hiện ra error message gốc
    EXEC sp_Payment
        @InvoiceId     = @InvoiceServicePendingId,
        @PaymentMethod = N'Chuyển khoản',
        @EmployeeId    = @TestEmployeeId;

    -- Kiểm tra invoice trên DB
    SELECT
        @DbInvoiceStatus = [status],
        @DbPaymentMethod = payment_method,
        @DbInvoiceEmpId  = employee_id
    FROM invoice
    WHERE id = @InvoiceServicePendingId;

    IF @DbInvoiceStatus <> N'Đã thanh toán'
        RAISERROR (N'TC07: Invoice.status không được cập nhật thành "Đã thanh toán".', 16, 1);

    IF @DbPaymentMethod <> N'Chuyển khoản'
        RAISERROR (N'TC07: Invoice.payment_method không đúng.', 16, 1);

    IF @DbInvoiceEmpId <> @TestEmployeeId
        RAISERROR (N'TC07: Invoice.employee_id không đúng.', 16, 1);

    -- Kiểm tra service_booking.status
    DECLARE @DbServiceStatus NVARCHAR(50);
    SELECT @DbServiceStatus = [status]
    FROM service_booking
    WHERE id = @ServiceBookingId;

    IF @DbServiceStatus <> N'Đã thanh toán'
        RAISERROR (N'TC07: service_booking.status không được cập nhật thành "Đã thanh toán".', 16, 1);

    -- Kiểm tra bonus_point
    SELECT @DbCustomerBonus = bonus_point
    FROM customer
    WHERE id = @TestCustomerId;

    IF @DbCustomerBonus <> @ExpectedAfter
        RAISERROR (N'TC07: Điểm thưởng sau khi cộng (dịch vụ) không đúng theo công thức. Expected: %d, Actual: %d', 16, 1, @ExpectedAfter, @DbCustomerBonus);

    PRINT N'--> [PASS] TC07: Thanh toán hóa đơn dịch vụ thành công, trạng thái & điểm thưởng đúng.';
END TRY
BEGIN CATCH
    PRINT N'--> [FAIL] TC07: ' + ERROR_MESSAGE();
    -- In thêm thông tin debug nếu có
    DECLARE @DebugStatus07 NVARCHAR(50);
    SELECT @DebugStatus07 = [status] FROM invoice WHERE id = @InvoiceServicePendingId;
    PRINT N'     [DEBUG] Invoice status hiện tại: ' + ISNULL(@DebugStatus07, N'NULL');
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- TC08: Thanh toán lại cùng hóa đơn dịch vụ → phải báo lỗi
------------------------------------------------------------
PRINT N'*** TC08: Thanh toán lại hóa đơn dịch vụ đã thanh toán → expect ERROR ***';

BEGIN TRY
    TRUNCATE TABLE #PaymentResult;

    EXEC sp_Payment
        @InvoiceId     = @InvoiceServicePendingId,
        @PaymentMethod = N'Chuyển khoản',
        @EmployeeId    = @TestEmployeeId;

    PRINT N'--> [FAIL] TC08: sp_Payment vẫn cho thanh toán lại hóa đơn dịch vụ.';
END TRY
BEGIN CATCH
    PRINT N'--> [PASS] TC08: Lỗi như mong đợi: ' + ERROR_MESSAGE();
END CATCH
PRINT '--------------------------------------------------------';

------------------------------------------------------------
-- 4. KHÔI PHỤC ĐIỂM & DỌN DẸP DỮ LIỆU TEST
------------------------------------------------------------
PRINT N'--- 4. Khôi phục bonus_point & dọn dữ liệu test ---';

-- Khôi phục điểm thưởng ban đầu cho khách test
UPDATE customer
SET bonus_point = @OriginalBonus
WHERE id = @TestCustomerId;

-- Xóa lại toàn bộ dữ liệu test đã tạo
DELETE I
FROM invoice I
WHERE I.court_booking_id IN (
        SELECT CB.id 
        FROM court_booking CB 
        WHERE CB.booked_base_price = @TestBasePrice
    )
   OR I.service_booking_id IN (
        SELECT SB.id
        FROM service_booking SB
        JOIN court_booking CB ON SB.court_booking_id = CB.id
        WHERE CB.booked_base_price = @TestBasePrice
    );

DELETE SB
FROM service_booking SB
JOIN court_booking CB ON SB.court_booking_id = CB.id
WHERE CB.booked_base_price = @TestBasePrice;

DELETE FROM court_booking
WHERE booked_base_price = @TestBasePrice;

PRINT N'--> Hoàn tất test sp_Payment.';
