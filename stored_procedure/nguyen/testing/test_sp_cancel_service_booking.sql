/*
 * =================================================================
 * TEST SCRIPT - sp_CancelServiceBooking
 * Người thực hiện : Nguyên (test)
 * Ngày            : 05/12/2025
 * Yêu cầu         :
 *   - Đã chạy:  create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:   sp_CancelServiceBooking (bản dùng N'Đã hủy', N'Chờ xử lý', N'Đã xử lý')
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 1: DỌN DẸP DỮ LIỆU TEST CŨ (NẾU CÓ)
 *   - Dựa trên marker: court_booking.booked_base_price = 123456.78
 *   - Và reason LIKE N'[TEST-SP-CANCEL]%'
 * ================================================================*/
PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

DECLARE @Today DATE = CAST(GETDATE() AS DATE);

;WITH TestCourtBooking AS
(
    SELECT CB.id
    FROM court_booking CB
    WHERE CB.[type] = N'Online'
      AND CB.[booking_date] > @Today
      AND CB.booked_base_price = 123456.78      -- marker test
),
TestServiceBooking AS
(
    SELECT SB.id
    FROM service_booking SB
    WHERE SB.court_booking_id IN (SELECT id FROM TestCourtBooking)
),
TestInvoice AS
(
    SELECT I.id
    FROM invoice I
    WHERE I.service_booking_id IN (SELECT id FROM TestServiceBooking)
),
TestRefund AS
(
    SELECT RI.id
    FROM refund_info RI
    WHERE RI.invoice_id IN (SELECT id FROM TestInvoice)
       OR RI.[reason] LIKE N'[TEST-SP-CANCEL]%'
)
-- 1. Xóa refund_info test
DELETE RI
FROM refund_info RI
WHERE RI.id IN (SELECT id FROM TestRefund);

-- 2. Xóa service_booking_item test
DELETE SBI
FROM service_booking_item SBI
WHERE SBI.service_booking_id IN (SELECT id FROM TestServiceBooking);

-- 3. Xóa invoice test
DELETE I
FROM invoice I
WHERE I.id IN (SELECT id FROM TestInvoice);

-- 4. Xóa service_booking test
DELETE SB
FROM service_booking SB
WHERE SB.id IN (SELECT id FROM TestServiceBooking);

-- 5. Xóa court_booking test
DELETE CB
FROM court_booking CB
WHERE CB.id IN (SELECT id FROM TestCourtBooking);

PRINT N'=== CLEANUP DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 2: CHUẨN BỊ DỮ LIỆU & BIẾN DÙNG CHUNG
 * ================================================================*/
PRINT N'=== PREPARE: Lấy khách hàng mẫu, branch, service, booking mẫu ===';

DECLARE
    @MainCustomerId          INT,
    @MainCustomerName        NVARCHAR(255),
    @OriginalBonusMain       INT,
    @TestBaseBonus           INT,

    @BranchHCMId             INT,
    @CourtHCMId              INT,
    @BranchServiceFutureId   INT,
    @UnitPriceFuture         DECIMAL(10, 2),
    @OriginalStockFuture     INT,

    @FutureBookingDate       DATE,
    @FutureStartTime         DATETIME,
    @FutureEndTime           DATETIME,
    @QtyFuture               INT,
    @CourtBookingFutureId    INT,
    @ServiceBookingFutureId  INT,
    @InvoiceFutureId         INT,

    @ServiceBookingSampleId  INT,
    @CourtBookingSampleId    INT;

-- Khách hàng mẫu: B (theo create_data.sql)
SELECT TOP 1
    @MainCustomerId    = id,
    @MainCustomerName  = full_name,
    @OriginalBonusMain = bonus_point
FROM customer
WHERE phone_number = '0902000002';

IF @MainCustomerId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy khách hàng mẫu (sđt 0902000002). Kiểm tra create_data.sql.', 16, 1);
    RETURN;
END

-- Chọn Branch TP.HCM
SELECT @BranchHCMId = id
FROM branch
WHERE [name] = N'VietSport TP.HCM';

IF @BranchHCMId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy chi nhánh VietSport TP.HCM.', 16, 1);
    RETURN;
END

-- Chọn 1 sân bất kỳ ở HCM
SELECT TOP 1 @CourtHCMId = id
FROM court
WHERE branch_id = @BranchHCMId
ORDER BY id;

IF @CourtHCMId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy sân nào ở chi nhánh HCM.', 16, 1);
    RETURN;
END

-- Chọn 1 branch_service còn hàng ở HCM
SELECT TOP 1
    @BranchServiceFutureId = id,
    @UnitPriceFuture       = unit_price,
    @OriginalStockFuture   = current_stock
FROM branch_service
WHERE branch_id = @BranchHCMId
  AND [status] = N'Còn'
ORDER BY id;

IF @BranchServiceFutureId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy branch_service còn hàng ở HCM.', 16, 1);
    RETURN;
END

-- Lấy service_booking mẫu từ create_data.sql (đã có invoice, đã thanh toán)
SELECT TOP 1
    @ServiceBookingSampleId = SB.id,
    @CourtBookingSampleId   = SB.court_booking_id
FROM service_booking SB
JOIN invoice I ON I.service_booking_id = SB.id
WHERE SB.[status] = N'Đã thanh toán'
  AND I.[status]  = N'Đã thanh toán'
ORDER BY SB.id;

IF @ServiceBookingSampleId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy service_booking mẫu (đã thanh toán).', 16, 1);
    RETURN;
END

PRINT N'  -> Khách hàng mẫu: ' + @MainCustomerName + N' (ID = ' + CAST(@MainCustomerId AS NVARCHAR(10)) + N')';
PRINT N'  -> Branch HCM ID           : ' + CAST(@BranchHCMId AS NVARCHAR(10));
PRINT N'  -> Court HCM ID            : ' + CAST(@CourtHCMId AS NVARCHAR(10));
PRINT N'  -> Branch Service Future ID: ' + CAST(@BranchServiceFutureId AS NVARCHAR(10));
PRINT N'  -> ServiceBooking mẫu ID   : ' + CAST(@ServiceBookingSampleId AS NVARCHAR(10));
PRINT N'';

-- Đặt lại bonus_point cho khách để test (ví dụ 1000 điểm)
SET @TestBaseBonus = 1000;
UPDATE customer
SET bonus_point = @TestBaseBonus
WHERE id = @MainCustomerId;

PRINT N'  -> Đặt bonus_point test cho khách = ' + CAST(@TestBaseBonus AS NVARCHAR(10));
PRINT N'';


/* ================================================================
 * PHẦN 3: TẠO COURT_BOOKING + SERVICE_BOOKING + INVOICE TEST (FUTURE)
 * ================================================================*/
PRINT N'=== PREPARE: Tạo booking & service_booking test trong TƯƠNG LAI ===';

SET @FutureBookingDate = CAST(DATEADD(DAY, 1, GETDATE()) AS DATE); -- ngày mai
SET @FutureStartTime   = DATEADD(HOUR, 1, GETDATE());
SET @FutureEndTime     = DATEADD(HOUR, 2, GETDATE());
SET @QtyFuture         = 3;  -- số lượng dịch vụ

-- Court booking test
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
    @FutureBookingDate,
    N'Online',
    N'Đã thanh toán',
    0,
    123456.78, -- marker để cleanup
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @CourtHCMId
);

SET @CourtBookingFutureId = SCOPE_IDENTITY();

-- Service booking test
INSERT INTO service_booking
(
    [status],
    [court_booking_id],
    [employee_id]
)
VALUES
(
    N'Đã thanh toán',
    @CourtBookingFutureId,
    NULL
);

SET @ServiceBookingFutureId = SCOPE_IDENTITY();

-- Service booking item test (slot trong tương lai)
INSERT INTO service_booking_item
(
    quantity,
    start_time,
    end_time,
    by_month,
    [status],
    booked_unit_price,
    service_booking_id,
    branch_service_id
)
VALUES
(
    @QtyFuture,
    @FutureStartTime,
    @FutureEndTime,
    0,
    N'Đã đặt',
    @UnitPriceFuture,
    @ServiceBookingFutureId,
    @BranchServiceFutureId
);

-- Invoice test cho dịch vụ
DECLARE @FutureInvoiceAmount DECIMAL(10, 2);
SET @FutureInvoiceAmount = @QtyFuture * @UnitPriceFuture;

INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    service_booking_id,
    employee_id
)
VALUES
(
    @FutureInvoiceAmount,
    N'Tiền mặt',
    N'Đã thanh toán',
    @ServiceBookingFutureId,
    NULL
);

SET @InvoiceFutureId = SCOPE_IDENTITY();

PRINT N'  -> CourtBookingFutureId    = ' + CAST(@CourtBookingFutureId AS NVARCHAR(10));
PRINT N'  -> ServiceBookingFutureId  = ' + CAST(@ServiceBookingFutureId AS NVARCHAR(10));
PRINT N'  -> InvoiceFutureId         = ' + CAST(@InvoiceFutureId AS NVARCHAR(10));
PRINT N'';


/* ================================================================
 * PHẦN 4: TEMP TABLE CHỨA KẾT QUẢ TỪ SP
 * ================================================================*/
IF OBJECT_ID('tempdb..#CancelServiceResult') IS NOT NULL
    DROP TABLE #CancelServiceResult;

CREATE TABLE #CancelServiceResult
(
    RefundId      INT,
    RefundAmount  DECIMAL(10, 2),
    Reason        NVARCHAR(500),
    RefundType    NVARCHAR(50),
    RefundMethod  NVARCHAR(50),
    RefundStatus  NVARCHAR(50),
    InvoiceId     INT,
    CreatedAt     DATETIME
);


/* ================================================================
 * PHẦN 5: CÁC TEST CASE
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_CancelServiceBooking';
PRINT N'============================================================';
PRINT N'';


/* ---------------------------------------------------------------
 * TC01: Happy path - Hủy dịch vụ còn slot chưa sử dụng (refund > 0)
 * ---------------------------------------------------------------*/
PRINT N'TC01 - Happy path: Hủy service_booking FUTURE (còn slot chưa dùng)';

BEGIN TRY
    DECLARE
        @StockBeforeTC1 INT,
        @StockAfterTC1  INT,
        @BonusBeforeTC1 INT,
        @BonusAfterTC1  INT,
        @BranchIdFuture INT,
        @LoyaltyRate    DECIMAL(5, 2),
        @ExpectedRefund DECIMAL(10, 2),
        @ExpectedBonusSubtract INT,
        @ExpectedBonusAfter   INT,
        @R1_Amount   DECIMAL(10, 2),
        @R1_Status   NVARCHAR(50),
        @R1_Invoice  INT,
        @SB_Status_After NVARCHAR(50);

    SELECT @StockBeforeTC1 = current_stock
    FROM branch_service
    WHERE id = @BranchServiceFutureId;

    SELECT @BonusBeforeTC1 = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    TRUNCATE TABLE #CancelServiceResult;

    INSERT INTO #CancelServiceResult
    EXEC sp_CancelServiceBooking
         @CourtBookingId   = @CourtBookingFutureId,
         @ServiceBookingId = @ServiceBookingFutureId,
         @Method           = N'Tiền mặt',
         @Type             = N'ServiceCancel',
         @Reason           = N'[TEST-SP-CANCEL] TC01 - Hủy dịch vụ còn slot';

    -- Kết quả phải có đúng 1 dòng
    IF (SELECT COUNT(*) FROM #CancelServiceResult) <> 1
        RAISERROR (N'TC01: SP không trả về đúng 1 dòng.', 16, 1);

    SELECT 
        @R1_Amount  = RefundAmount,
        @R1_Status  = RefundStatus,
        @R1_Invoice = InvoiceId
    FROM #CancelServiceResult;

    SELECT @StockAfterTC1 = current_stock
    FROM branch_service
    WHERE id = @BranchServiceFutureId;

    SELECT @BonusAfterTC1 = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    -- Tính toán expected
    SET @ExpectedRefund = @QtyFuture * @UnitPriceFuture;

    SELECT @BranchIdFuture = branch_id
    FROM branch_service
    WHERE id = @BranchServiceFutureId;

    SELECT @LoyaltyRate = loyalty_point_rate
    FROM branch
    WHERE id = @BranchIdFuture;

    SET @ExpectedBonusSubtract = CAST(@ExpectedRefund * @LoyaltyRate AS INT);
    IF @ExpectedBonusSubtract < 0 SET @ExpectedBonusSubtract = 0;

    SET @ExpectedBonusAfter =
        CASE WHEN @TestBaseBonus < @ExpectedBonusSubtract
             THEN 0
             ELSE @TestBaseBonus - @ExpectedBonusSubtract
        END;

    -- Kiểm tra tồn kho tăng đúng
    IF @StockAfterTC1 <> @StockBeforeTC1 + @QtyFuture
        RAISERROR (N'TC01: current_stock không tăng đúng bằng quantity chưa dùng.', 16, 1);

    -- Kiểm tra điểm thưởng
    IF @BonusBeforeTC1 <> @TestBaseBonus
        RAISERROR (N'TC01: BonusPointBefore của customer không đúng.', 16, 1);

    IF @BonusAfterTC1 <> @ExpectedBonusAfter
        RAISERROR (N'TC01: BonusPointAfter của customer không đúng.', 16, 1);

    -- Kiểm tra thông tin hoàn tiền
    IF @R1_Amount <> @ExpectedRefund
        RAISERROR (N'TC01: RefundAmount trả về không khớp với expected.', 16, 1);

    IF @R1_Invoice <> @InvoiceFutureId
        RAISERROR (N'TC01: InvoiceId hoàn tiền không đúng.', 16, 1);

    IF @R1_Status <> N'Chờ xử lý'
        RAISERROR (N'TC01: RefundStatus không phải ''Chờ xử lý'' cho trường hợp refund > 0.', 16, 1);

    -- Kiểm tra service_booking.status
    SELECT @SB_Status_After = [status]
    FROM service_booking
    WHERE id = @ServiceBookingFutureId;

    IF @SB_Status_After <> N'Đã hủy'
        RAISERROR (N'TC01: service_booking.status sau khi hủy phải = N''Đã hủy''.', 16, 1);

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC02: Hủy lại cùng service_booking (đã Đã hủy) → phải báo lỗi
 * ---------------------------------------------------------------*/
PRINT N'TC02 - Hủy lại cùng service_booking FUTURE (đã hủy)';

BEGIN TRY
    EXEC sp_CancelServiceBooking
         @CourtBookingId   = @CourtBookingFutureId,
         @ServiceBookingId = @ServiceBookingFutureId,
         @Method           = N'Tiền mặt',
         @Type             = N'ServiceCancel',
         @Reason           = N'[TEST-SP-CANCEL] TC02 - Hủy lần 2';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC03: service_booking tồn tại nhưng court_booking_id sai
 * ---------------------------------------------------------------*/
PRINT N'TC03 - court_booking_id không khớp với service_booking';

BEGIN TRY
    DECLARE @WrongCourtId INT = @CourtBookingFutureId + 9999;

    EXEC sp_CancelServiceBooking
         @CourtBookingId   = @WrongCourtId,
         @ServiceBookingId = @ServiceBookingSampleId,
         @Method           = N'Tiền mặt',
         @Type             = N'ServiceCancel',
         @Reason           = N'[TEST-SP-CANCEL] TC03 - CourtBookingId sai';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC04: service_booking không có invoice → phải báo lỗi
 * ---------------------------------------------------------------*/
PRINT N'TC04 - service_booking không có invoice';

BEGIN TRY
    DECLARE @ServiceBookingNoInvoiceId INT;

    INSERT INTO service_booking ([status], [court_booking_id], [employee_id])
    VALUES (N'Đã thanh toán', @CourtBookingFutureId, NULL);

    SET @ServiceBookingNoInvoiceId = SCOPE_IDENTITY();

    EXEC sp_CancelServiceBooking
         @CourtBookingId   = @CourtBookingFutureId,
         @ServiceBookingId = @ServiceBookingNoInvoiceId,
         @Method           = N'Tiền mặt',
         @Type             = N'ServiceCancel',
         @Reason           = N'[TEST-SP-CANCEL] TC04 - Không có invoice';

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC05: Hủy service_booking mẫu (slot đã qua, không còn dịch vụ chưa dùng)
 *   - RefundAmount = 0
 *   - Tồn kho & bonus_point không đổi
 *   - RefundStatus = N'Đã xử lý'
 * ---------------------------------------------------------------*/
PRINT N'TC05 - Hủy service_booking mẫu (không có slot > NOW)';

BEGIN TRY
    DECLARE
        @BS_SampleId      INT,
        @StockBeforeTC5   INT,
        @StockAfterTC5    INT,
        @BonusBeforeTC5   INT,
        @BonusAfterTC5    INT,
        @R5_Amount        DECIMAL(10, 2),
        @R5_Status        NVARCHAR(50),
        @SB_Status_After5 NVARCHAR(50);

    SELECT TOP 1 @BS_SampleId = branch_service_id
    FROM service_booking_item
    WHERE service_booking_id = @ServiceBookingSampleId
    ORDER BY id;

    SELECT @StockBeforeTC5 = current_stock
    FROM branch_service
    WHERE id = @BS_SampleId;

    SELECT @BonusBeforeTC5 = bonus_point
    FROM customer C
    JOIN court_booking CB ON CB.customer_id = C.id
    JOIN service_booking SB ON SB.court_booking_id = CB.id
    WHERE SB.id = @ServiceBookingSampleId;

    TRUNCATE TABLE #CancelServiceResult;

    INSERT INTO #CancelServiceResult
    EXEC sp_CancelServiceBooking
         @CourtBookingId   = @CourtBookingSampleId,
         @ServiceBookingId = @ServiceBookingSampleId,
         @Method           = N'Tiền mặt',
         @Type             = N'ServiceCancel',
         @Reason           = N'[TEST-SP-CANCEL] TC05 - ServiceBooking mẫu';

    IF (SELECT COUNT(*) FROM #CancelServiceResult) <> 1
        RAISERROR (N'TC05: SP không trả về đúng 1 dòng.', 16, 1);

    SELECT 
        @R5_Amount = RefundAmount,
        @R5_Status = RefundStatus
    FROM #CancelServiceResult;

    SELECT @StockAfterTC5 = current_stock
    FROM branch_service
    WHERE id = @BS_SampleId;

    SELECT @BonusAfterTC5 = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    -- Vì start_time đều < GETDATE() nên RefundAmount = 0, stock & bonus không đổi
    IF @R5_Amount <> 0
        RAISERROR (N'TC05: RefundAmount phải = 0 khi không có dịch vụ chưa dùng.', 16, 1);

    IF @StockAfterTC5 <> @StockBeforeTC5
        RAISERROR (N'TC05: current_stock bị thay đổi dù không có dịch vụ chưa dùng.', 16, 1);

    IF @BonusAfterTC5 <> @BonusBeforeTC5
        RAISERROR (N'TC05: bonus_point bị thay đổi dù RefundAmount = 0.', 16, 1);

    IF @R5_Status <> N'Đã xử lý'
        RAISERROR (N'TC05: RefundStatus phải = N''Đã xử lý'' khi số tiền hoàn = 0.', 16, 1);

    SELECT @SB_Status_After5 = [status]
    FROM service_booking
    WHERE id = @ServiceBookingSampleId;

    IF @SB_Status_After5 <> N'Đã hủy'
        RAISERROR (N'TC05: service_booking.status sau khi hủy phải = N''Đã hủy''.', 16, 1);

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * PHẦN 6: RESTORE DỮ LIỆU
 * ================================================================*/
PRINT N'=== RESTORE: Khôi phục dữ liệu sau test ===';

-- 1. Xóa refund_info test (theo reason hoặc invoice future)
DELETE RI
FROM refund_info RI
WHERE RI.[reason] LIKE N'[TEST-SP-CANCEL]%'
   OR RI.invoice_id = @InvoiceFutureId;

-- 2. Xóa invoice test future
DELETE FROM invoice
WHERE id = @InvoiceFutureId;

-- 3. Xóa service_booking_item test
DELETE FROM service_booking_item
WHERE service_booking_id = @ServiceBookingFutureId;

-- 4. Xóa tất cả service_booking gắn với court_booking future (bao gồm cái TC04 tạo không có invoice)
DELETE FROM service_booking
WHERE court_booking_id = @CourtBookingFutureId;

-- 5. Xóa court_booking future test
DELETE FROM court_booking
WHERE id = @CourtBookingFutureId;

-- Đặt lại status của service_booking mẫu về 'Đã thanh toán'
UPDATE service_booking
SET [status] = N'Đã thanh toán'
WHERE id = @ServiceBookingSampleId;

-- Khôi phục tồn kho gốc của branch_service dùng cho TC01
UPDATE branch_service
SET current_stock = @OriginalStockFuture
WHERE id = @BranchServiceFutureId;

-- Khôi phục bonus gốc cho khách hàng mẫu
UPDATE customer
SET bonus_point = @OriginalBonusMain
WHERE id = @MainCustomerId;

PRINT N'=== RESTORE DONE ===';
PRINT N'';
PRINT N'============================================================';
PRINT N'KẾT THÚC TEST sp_CancelServiceBooking';
PRINT N'============================================================';
