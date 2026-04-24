/*
 * =================================================================
 * TEST SCRIPT - sp_SearchCourtDailySchedule
 * Người thực hiện : Nguyên (test)
 * Ngày            : 06/12/2025
 * Yêu cầu         :
 *   - Đã chạy: create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:  sp_SearchCourtDailySchedule
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: CLEANUP DỮ LIỆU TEST CŨ (NẾU CÓ)
 * ================================================================*/

PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

-- Xóa invoice test (theo marker booked_base_price = 98765.43)
DELETE I
FROM invoice I
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43
  AND CB.[type] = N'Online';

-- Xóa booking_slots test
DELETE FROM booking_slots
WHERE court_booking_id IN (
    SELECT id
    FROM court_booking
    WHERE booked_base_price = 98765.43
      AND [type] = N'Online'
);

-- Xóa court_booking test
DELETE FROM court_booking
WHERE booked_base_price = 98765.43
  AND [type] = N'Online';

PRINT N'=== CLEANUP DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU CHUNG
 *   - Lấy 1 sân test + rent_duration + branch (open/close)
 *   - Lấy 1 khách hàng mẫu (B – phone 0902000002)
 *   - Tính số slot trong ngày từ open_time → close_time
 *   - Xác định 3 slot đầu tiên
 * ================================================================*/

PRINT N'=== PREPARE: Lấy sân test, khách test, tính số slot ===';

DECLARE
    @TestCourtId          INT,
    @RentDuration         INT,
    @BranchId             INT,
    @OpenTime             TIME,
    @CloseTime            TIME,

    @MainCustomerId       INT,
    @MainCustomerName     NVARCHAR(255),

    @FutureDate           DATE,
    @PastDate             DATE,
    @StartOfDayFuture     DATETIME,
    @EndOfDayFuture       DATETIME,
    @ExpectedSlotCount    INT,

    @Slot1Start           DATETIME,
    @Slot1End             DATETIME,
    @Slot2Start           DATETIME,
    @Slot2End             DATETIME,
    @Slot3Start           DATETIME,
    @Slot3End             DATETIME;

-- 1.1. Chọn 1 sân bất kỳ + rent_duration + branch (open/close)
SELECT TOP 1
    @TestCourtId  = C.id,
    @RentDuration = CT.rent_duration,
    @BranchId     = C.branch_id,
    @OpenTime     = B.open_time,
    @CloseTime    = B.close_time
FROM court C
JOIN court_type CT ON C.court_type_id = CT.id
JOIN branch B      ON C.branch_id     = B.id
ORDER BY C.id;

IF @TestCourtId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy sân nào trong hệ thống.', 16, 1);
    RETURN;
END

IF @RentDuration IS NULL OR @RentDuration <= 0
BEGIN
    RAISERROR (N'rent_duration của sân test không hợp lệ.', 16, 1);
    RETURN;
END

IF @OpenTime IS NULL OR @CloseTime IS NULL
BEGIN
    RAISERROR (N'Không xác định được open_time/close_time của chi nhánh.', 16, 1);
    RETURN;
END

-- 1.2. Lấy khách hàng mẫu (B – sđt 0902000002)
SELECT TOP 1
    @MainCustomerId   = id,
    @MainCustomerName = full_name
FROM customer
WHERE phone_number = '0902000002';

IF @MainCustomerId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy khách hàng mẫu (phone = 0902000002).', 16, 1);
    RETURN;
END

-- 1.3. Ngày tương lai & quá khứ cho test
SET @FutureDate = DATEADD(YEAR, 1, CAST(GETDATE() AS DATE));   -- năm sau
SET @PastDate   = DATEADD(YEAR,-1, CAST(GETDATE() AS DATE));   -- năm trước

-- 1.4. Tính số slot trong ngày theo logic SP (open_time → close_time)
DECLARE
    @TmpStart   DATETIME,
    @StartOfDay DATETIME,
    @EndOfDay   DATETIME;

-- Kết hợp ngày với open_time/close_time giống trong SP
SET @StartOfDay = DATEADD(SECOND,
                          DATEDIFF(SECOND, CAST('00:00:00' AS TIME), @OpenTime),
                          CAST(@FutureDate AS DATETIME));
SET @EndOfDay   = DATEADD(SECOND,
                          DATEDIFF(SECOND, CAST('00:00:00' AS TIME), @CloseTime),
                          CAST(@FutureDate AS DATETIME));

SET @TmpStart = @StartOfDay;
SET @ExpectedSlotCount = 0;

WHILE @TmpStart < @EndOfDay
BEGIN
    SET @ExpectedSlotCount = @ExpectedSlotCount + 1;
    SET @TmpStart = DATEADD(MINUTE, @RentDuration, @TmpStart);
END

SET @StartOfDayFuture = @StartOfDay;
SET @EndOfDayFuture   = @EndOfDay;

-- 1.5. Tính 3 slot đầu tiên
SET @Slot1Start = @StartOfDayFuture;
SET @Slot1End   = DATEADD(MINUTE, @RentDuration, @Slot1Start);

SET @Slot2Start = @Slot1End;
SET @Slot2End   = DATEADD(MINUTE, @RentDuration, @Slot2Start);

SET @Slot3Start = @Slot2End;
SET @Slot3End   = DATEADD(MINUTE, @RentDuration, @Slot3Start);

PRINT N'  -> Court test ID        = ' + CAST(@TestCourtId AS NVARCHAR(10));
PRINT N'  -> Branch ID            = ' + CAST(@BranchId AS NVARCHAR(10));
PRINT N'  -> open_time            = ' + CONVERT(NVARCHAR(8), @OpenTime, 108);
PRINT N'  -> close_time           = ' + CONVERT(NVARCHAR(8), @CloseTime, 108);
PRINT N'  -> rent_duration (phút) = ' + CAST(@RentDuration AS NVARCHAR(10));
PRINT N'  -> Số slot / ngày       = ' + CAST(@ExpectedSlotCount AS NVARCHAR(10));
PRINT N'';


/* ================================================================
 * PHẦN 2: TẠO BOOKING/INVOICE TEST CHO NGÀY TƯƠNG LAI
 *   Slot 1: invoice Đã thanh toán   -> "Đã đặt"
 *   Slot 2: invoice Chưa thanh toán -> "Chờ xác nhận"
 *   Slot 3: không booking           -> "Trống"
 * ================================================================*/

PRINT N'=== PREPARE: Tạo dữ liệu booking/invoice cho ngày tương lai ===';

DECLARE
    @CourtBookingPaidId     INT,
    @CourtBookingPendingId  INT,
    @InvoicePaidId          INT,
    @InvoicePendingId       INT,
    @CreatedAtPaid          DATETIME,
    @CreatedAtPending       DATETIME;

-- Tính created_at để tuân thủ trigger R1402: đặt sân online phải trước giờ bắt đầu ít nhất 2 giờ
-- Đặt created_at = slot_start - 3 giờ để đảm bảo an toàn
SET @CreatedAtPaid    = DATEADD(HOUR, -3, @Slot1Start);  -- trước slot1 3 giờ
SET @CreatedAtPending = DATEADD(HOUR, -3, @Slot2Start);  -- trước slot2 3 giờ

-- Booking 1: dùng cho slot 1 (Đã thanh toán)
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
    @FutureDate,
    N'Online',
    N'Đã thanh toán',
    0,
    98765.43,      -- marker test
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @CreatedAtPaid
);

SET @CourtBookingPaidId = SCOPE_IDENTITY();

INSERT INTO booking_slots
(
    start_time,
    end_time,
    [status],
    night_charge,
    court_booking_id
)
VALUES
(
    @Slot1Start,
    @Slot1End,
    N'Đã đặt',
    0.00,
    @CourtBookingPaidId
);

INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    court_booking_id,
    employee_id
)
VALUES
(
    100000.00,
    N'Tiền mặt',  -- giá trị hợp lệ theo constraint CK_R1112
    N'Đã thanh toán',
    @CourtBookingPaidId,
    NULL
);

SET @InvoicePaidId = SCOPE_IDENTITY();

-- Booking 2: dùng cho slot 2 (Chưa thanh toán)
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
    @FutureDate,
    N'Online',
    N'Chưa thanh toán',
    0,
    98765.43,    -- marker test
    0.00,
    0.00,
    @MainCustomerId,
    NULL,
    @TestCourtId,
    @CreatedAtPending
);

SET @CourtBookingPendingId = SCOPE_IDENTITY();

INSERT INTO booking_slots
(
    start_time,
    end_time,
    [status],
    night_charge,
    court_booking_id
)
VALUES
(
    @Slot2Start,
    @Slot2End,
    N'Đã đặt',
    0.00,
    @CourtBookingPendingId
);

INSERT INTO invoice
(
    total_amount,
    payment_method,
    [status],
    court_booking_id,
    employee_id
)
VALUES
(
    80000.00,
    N'Tiền mặt',  -- giá trị hợp lệ theo constraint CK_R1112
    N'Chưa thanh toán',
    @CourtBookingPendingId,
    NULL
);

SET @InvoicePendingId = SCOPE_IDENTITY();

PRINT N'=== PREPARE DATA DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 3: TEMP TABLE ĐỂ BẮT KẾT QUẢ
 * ================================================================*/

IF OBJECT_ID('tempdb..#Schedule') IS NOT NULL
    DROP TABLE #Schedule;

CREATE TABLE #Schedule
(
    KhungGio   NVARCHAR(50),
    TrangThai  NVARCHAR(50),
    StartTime  DATETIME,
    EndTime    DATETIME
);


/* ================================================================
 * PHẦN 4: TEST CASES
 * ================================================================*/

PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_SearchCourtDailySchedule';
PRINT N'============================================================';
PRINT N'';


/* ---------------------------------------------------------------
 * TC01: Happy path (ngày tương lai)
 *   - Số slot = ExpectedSlotCount
 *   - Slot1 -> "Đã đặt"
 *   - Slot2 -> "Chờ xác nhận"
 *   - Slot3 -> "Trống"
 * ---------------------------------------------------------------*/
PRINT N'TC01 - Happy path: ngày tương lai, 3 trạng thái Đã đặt / Chờ xác nhận / Trống';

BEGIN TRY
    TRUNCATE TABLE #Schedule;

    INSERT INTO #Schedule
    EXEC sp_SearchCourtDailySchedule
         @BookingDate = @FutureDate,
         @CourtId     = @TestCourtId;

    -- Kiểm tra số slot
    IF (SELECT COUNT(*) FROM #Schedule) <> @ExpectedSlotCount
    BEGIN
        RAISERROR (N'TC01: Số slot trả về không bằng ExpectedSlotCount.', 16, 1);
    END

    -- Slot1: Đã đặt
    IF NOT EXISTS (
        SELECT 1 FROM #Schedule
        WHERE StartTime = @Slot1Start
          AND EndTime   = @Slot1End
          AND TrangThai = N'Đã đặt'
    )
    BEGIN
        RAISERROR (N'TC01: Slot 1 không có trạng thái "Đã đặt" như mong đợi.', 16, 1);
    END

    -- Slot2: Chờ xác nhận
    IF NOT EXISTS (
        SELECT 1 FROM #Schedule
        WHERE StartTime = @Slot2Start
          AND EndTime   = @Slot2End
          AND TrangThai = N'Chờ xác nhận'
    )
    BEGIN
        RAISERROR (N'TC01: Slot 2 không có trạng thái "Chờ xác nhận" như mong đợi.', 16, 1);
    END

    -- Slot3: Trống
    IF NOT EXISTS (
        SELECT 1 FROM #Schedule
        WHERE StartTime = @Slot3Start
          AND EndTime   = @Slot3End
          AND TrangThai = N'Trống'
    )
    BEGIN
        RAISERROR (N'TC01: Slot 3 không có trạng thái "Trống" như mong đợi.', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
    PRINT N'  => KẾT QUẢ CHI TIẾT:';
    SELECT 
        KhungGio,
        TrangThai,
        CONVERT(NVARCHAR(19), StartTime, 120) AS StartTime,
        CONVERT(NVARCHAR(19), EndTime, 120) AS EndTime
    FROM #Schedule
    ORDER BY StartTime;
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH

PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC02: Ngày trong quá khứ
 *   - Tất cả slot phải là "Đã qua"
 * ---------------------------------------------------------------*/
PRINT N'TC02 - Ngày trong quá khứ: toàn bộ slot = "Đã qua"';

BEGIN TRY
    TRUNCATE TABLE #Schedule;

    INSERT INTO #Schedule
    EXEC sp_SearchCourtDailySchedule
         @BookingDate = @PastDate,
         @CourtId     = @TestCourtId;

    -- Số slot phải bằng ExpectedSlotCount
    IF (SELECT COUNT(*) FROM #Schedule) <> @ExpectedSlotCount
    BEGIN
        RAISERROR (N'TC02: Số slot trả về không bằng ExpectedSlotCount.', 16, 1);
    END

    -- Không được có slot nào khác "Đã qua"
    IF EXISTS (
        SELECT 1 FROM #Schedule
        WHERE TrangThai <> N'Đã qua'
    )
    BEGIN
        RAISERROR (N'TC02: Có slot không phải trạng thái "Đã qua".', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
    
    -- Hiển thị kết quả
    PRINT N'  => KẾT QUẢ CHI TIẾT:';
    SELECT 
        KhungGio,
        TrangThai,
        CONVERT(NVARCHAR(19), StartTime, 120) AS StartTime,
        CONVERT(NVARCHAR(19), EndTime, 120) AS EndTime
    FROM #Schedule
    ORDER BY StartTime;
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH

PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC03: CourtId không tồn tại
 *   - Expect: SP báo lỗi (do rent_duration không xác định)
 * ---------------------------------------------------------------*/
PRINT N'TC03 - CourtId không tồn tại';

BEGIN TRY
    DECLARE @FakeCourtId INT;
    SELECT @FakeCourtId = ISNULL(MAX(id), 0) + 1000 FROM court;

    EXEC sp_SearchCourtDailySchedule
         @BookingDate = @FutureDate,
         @CourtId     = @FakeCourtId;

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH

PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC04: CourtId = NULL
 *   - Expect: SP báo lỗi "Không tìm thấy sân phù hợp với các điều kiện đầu vào."
 * ---------------------------------------------------------------*/
PRINT N'TC04 - CourtId = NULL';

BEGIN TRY
    EXEC sp_SearchCourtDailySchedule
         @BookingDate = @FutureDate,
         @CourtId     = NULL;

    PRINT N'  => KẾT QUẢ: FAIL (đáng ra phải báo lỗi nhưng SP chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (nhận lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH

PRINT N'------------------------------------------------------------';


PRINT N'============================================================';
PRINT N'KẾT THÚC TEST sp_SearchCourtDailySchedule';
PRINT N'============================================================';


/* ================================================================
 * PHẦN 5: CLEANUP LẠI DỮ LIỆU TEST
 * ================================================================*/

PRINT N'=== FINAL CLEANUP: Xóa dữ liệu test ===';

-- Xóa theo thứ tự FK (từ con lên cha)
-- 1. Xóa invoice test (theo marker booked_base_price = 98765.43)
DELETE I
FROM invoice I
JOIN court_booking CB ON I.court_booking_id = CB.id
WHERE CB.booked_base_price = 98765.43;

-- 2. Xóa booking_slots test
DELETE FROM booking_slots
WHERE court_booking_id IN (
    SELECT id
    FROM court_booking
    WHERE booked_base_price = 98765.43
);

-- 3. Xóa court_booking test
DELETE FROM court_booking
WHERE booked_base_price = 98765.43;

PRINT N'=== CLEANUP HOÀN TẤT ===';
