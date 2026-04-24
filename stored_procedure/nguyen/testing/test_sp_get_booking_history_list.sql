/*
 * =================================================================
 * TEST SCRIPT - sp_GetCourtBookingHistoryByCustomer
 * Người thực hiện : Nguyên (test)
 * Ngày            : 05/12/2025
 * Yêu cầu         :
 *   - Đã chạy: create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:  sp_GetCourtBookingHistoryByCustomer
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: DỌN DẸP DỮ LIỆU TEST CŨ (NẾU CÓ)
 *   - Xóa các booking/invoice có type hoặc payment_method dùng cho test
 * ================================================================*/

PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

-- Xóa invoice test
DELETE FROM [invoice]
WHERE [payment_method] LIKE 'TEST-SP-HISTORY%';

-- Xóa booking_slots test
DELETE FROM [booking_slots]
WHERE [court_booking_id] IN (
    SELECT id FROM [court_booking] WHERE [type] LIKE N'TEST-SP-HISTORY%'
);

-- Xóa court_booking test
DELETE FROM [court_booking]
WHERE [type] LIKE N'TEST-SP-HISTORY%';

PRINT N'=== CLEANUP DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU CẦN THIẾT
 *   - Lấy khách hàng mẫu (Trần Thị B - sđt 0902000002)
 *   - Lấy booking mẫu:
 *       + HCM: Đã thanh toán online
 *       + Cần Thơ: Chưa thanh toán (chưa có hóa đơn)
 *   - Tạo thêm 1 booking "Đã hủy" cho cùng khách
 * ================================================================*/

DECLARE 
    @CustomerIdBase       INT,
    @BookingPaidId        INT,
    @BookingUnpaidId      INT,
    @BookingCancelId      INT,
    @TestCourtId          INT;

PRINT N'=== PREPARE: Lấy khách hàng & booking mẫu ===';

-- Khách hàng mẫu từ create_data.sql
SELECT @CustomerIdBase = id
FROM [customer]
WHERE [phone_number] = '0902000002';

IF @CustomerIdBase IS NULL
BEGIN
    RAISERROR (
        N'Không tìm thấy khách mẫu (phone = 0902000002). Hãy kiểm tra create_data.sql đã chạy.',
        16, 1
    );
    RETURN;
END

-- Booking mẫu 1: Đã thanh toán (HCM - Online)
SELECT TOP 1 @BookingPaidId = id
FROM [court_booking]
WHERE [customer_id] = @CustomerIdBase
  AND [status] = N'Đã thanh toán'
ORDER BY id;

IF @BookingPaidId IS NULL
BEGIN
    RAISERROR (
        N'Không tìm thấy Booking mẫu (Đã thanh toán) cho khách hàng mẫu.',
        16, 1
    );
    RETURN;
END

-- Booking mẫu 2: Chưa thanh toán (Cần Thơ - Trực tiếp)
SELECT TOP 1 @BookingUnpaidId = id
FROM [court_booking]
WHERE [customer_id] = @CustomerIdBase
  AND [status] = N'Chưa thanh toán'
ORDER BY id;

IF @BookingUnpaidId IS NULL
BEGIN
    RAISERROR (
        N'Không tìm thấy Booking mẫu (Chưa thanh toán) cho khách hàng mẫu.',
        16, 1
    );
    RETURN;
END

-- Lấy court_id dùng cho booking test "Đã hủy"
SELECT @TestCourtId = [court_id]
FROM [court_booking]
WHERE id = @BookingPaidId;

IF @TestCourtId IS NULL
    SELECT TOP 1 @TestCourtId = id FROM [court] ORDER BY id;

PRINT N'=== PREPARE: Tạo booking test "Đã hủy" ===';

-- Tạo thêm 1 booking "Đã hủy" cho cùng khách
INSERT INTO [court_booking]
(
    [type],
    [status],
    [by_month],
    [booked_base_price],
    [holiday_charge],
    [weekend_charge],
    [customer_id],
    [employee_id],
    [court_id],
    [booking_date],
    [created_at]
)
VALUES
(
    N'Online',  -- Đánh dấu booking test
    N'Đã hủy',
    0,
    100000.00,
    0.00,
    0.00,
    @CustomerIdBase,
    NULL,              -- Không có nhân viên
    @TestCourtId,
    '2024-06-30',
    '2024-06-29 10:00:00'
);

SET @BookingCancelId = SCOPE_IDENTITY();

-- Thêm 1 slot cho booking "Đã hủy"
INSERT INTO [booking_slots]
(
    [start_time],
    [end_time],
    [status],
    [night_charge],
    [court_booking_id]
)
VALUES
(
    '2024-06-30 10:00:00',
    '2024-06-30 11:00:00',
    N'Đã đặt',
    0.00,
    @BookingCancelId
);

PRINT N'=== PREPARE DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 2: CHUẨN BỊ GIÁ TRỊ EXPECTED (Mã booking cho 3 booking chính)
 *   - Tính Mã booking giống logic trong SP:
 *       VS-<id_booking>-<yyyymmdd> (yyyymmdd lấy từ Min(start_time) hoặc created_at)
 * ================================================================*/

DECLARE
    @MinStartPaid    DATE,
    @MinStartUnpaid  DATE,
    @MinStartCancel  DATE,
    @CreatedPaid     DATE,
    @CreatedUnpaid   DATE,
    @CreatedCancel   DATE,
    @CodePaid        NVARCHAR(50),
    @CodeUnpaid      NVARCHAR(50),
    @CodeCancel      NVARCHAR(50);

-- Min start time
SELECT @MinStartPaid = MIN(CAST([start_time] AS DATE))
FROM [booking_slots]
WHERE [court_booking_id] = @BookingPaidId;

SELECT @MinStartUnpaid = MIN(CAST([start_time] AS DATE))
FROM [booking_slots]
WHERE [court_booking_id] = @BookingUnpaidId;

SELECT @MinStartCancel = MIN(CAST([start_time] AS DATE))
FROM [booking_slots]
WHERE [court_booking_id] = @BookingCancelId;

-- Created_at (ngày)
SELECT @CreatedPaid   = CAST([created_at] AS DATE) FROM [court_booking] WHERE id = @BookingPaidId;
SELECT @CreatedUnpaid = CAST([created_at] AS DATE) FROM [court_booking] WHERE id = @BookingUnpaidId;
SELECT @CreatedCancel = CAST([created_at] AS DATE) FROM [court_booking] WHERE id = @BookingCancelId;

-- Mã booking
SET @CodePaid = 'VS-' + CAST(@BookingPaidId AS VARCHAR(10)) + '-' +
                CONVERT(CHAR(8), ISNULL(@MinStartPaid, @CreatedPaid), 112);

SET @CodeUnpaid = 'VS-' + CAST(@BookingUnpaidId AS VARCHAR(10)) + '-' +
                  CONVERT(CHAR(8), ISNULL(@MinStartUnpaid, @CreatedUnpaid), 112);

SET @CodeCancel = 'VS-' + CAST(@BookingCancelId AS VARCHAR(10)) + '-' +
                  CONVERT(CHAR(8), ISNULL(@MinStartCancel, @CreatedCancel), 112);


/* ================================================================
 * PHẦN 3: GỌI SP VÀ LƯU KẾT QUẢ VÀO TEMP TABLE
 * ================================================================*/

IF OBJECT_ID('tempdb..#CourtBookingHistory') IS NOT NULL
    DROP TABLE #CourtBookingHistory;

CREATE TABLE #CourtBookingHistory
(
    [Mã booking]   NVARCHAR(50),
    [Sân]          NVARCHAR(255),
    [Loại sân]     NVARCHAR(255),
    [Khách hàng]   NVARCHAR(255),
    [Nhân viên]    NVARCHAR(255),
    [Thời gian]    NVARCHAR(MAX),
    [TT Thanh toán] NVARCHAR(50)
);

INSERT INTO #CourtBookingHistory
EXEC sp_GetCourtBookingHistoryByCustomer @CustomerId = @CustomerIdBase;

PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_GetCourtBookingHistoryByCustomer';
PRINT N'Khách hàng mẫu ID = ' + CAST(@CustomerIdBase AS VARCHAR(10));
PRINT N'============================================================';
PRINT N'';


/* ================================================================
 * TC01: Khách hàng có lịch sử đặt sân (>= 3 booking)
 * ================================================================*/
PRINT N'TC01 - Khách hàng mẫu có ít nhất 3 phiếu đặt sân (bao gồm booking test "Đã hủy")';
BEGIN TRY
    IF (SELECT COUNT(*) FROM #CourtBookingHistory) < 3
    BEGIN
        RAISERROR (N'TC01: Kỳ vọng >= 3 dòng, nhưng thực tế ít hơn.', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * TC02: Booking đã thanh toán
 *   - TT Thanh toán = "Đã thanh toán"
 *   - Nếu employee_id NULL thì Nhân viên = "-"
 * ================================================================*/
PRINT N'TC02 - Booking đã thanh toán (HCM - Online)';
BEGIN TRY
    -- Kiểm tra trạng thái thanh toán
    IF NOT EXISTS (
        SELECT 1
        FROM #CourtBookingHistory
        WHERE [Mã booking]   = @CodePaid
          AND [TT Thanh toán] = N'Đã thanh toán'
    )
    BEGIN
        RAISERROR (N'TC02: Không tìm thấy dòng với TT Thanh toán = "Đã thanh toán" cho booking đã thanh toán.', 16, 1);
    END

    -- Nếu employee_id NULL thì Nhân viên phải là "-"
    IF EXISTS (SELECT 1 FROM [court_booking] WHERE id = @BookingPaidId AND [employee_id] IS NULL)
    BEGIN
        IF NOT EXISTS (
            SELECT 1
            FROM #CourtBookingHistory
            WHERE [Mã booking] = @CodePaid
              AND [Nhân viên]  = N'-'
        )
        BEGIN
            RAISERROR (N'TC02: Booking có employee_id NULL nhưng cột [Nhân viên] không hiển thị "-".', 16, 1);
        END
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * TC03: Booking chưa thanh toán, chưa có hóa đơn
 *   - TT Thanh toán = "Chưa có hóa đơn"
 *   - Nhân viên = tên nhân viên từ bảng employee (nếu có)
 * ================================================================*/
PRINT N'TC03 - Booking chưa thanh toán (Cần Thơ - Trực tiếp, chưa có hóa đơn)';
BEGIN TRY
    -- TT Thanh toán
    IF NOT EXISTS (
        SELECT 1
        FROM #CourtBookingHistory
        WHERE [Mã booking]   = @CodeUnpaid
          AND [TT Thanh toán] = N'Chưa có hóa đơn'
    )
    BEGIN
        RAISERROR (N'TC03: Booking chưa thanh toán nhưng TT Thanh toán không phải "Chưa có hóa đơn".', 16, 1);
    END

    -- Nhân viên
    DECLARE @ExpectedEmpUnpaid NVARCHAR(255);
    SELECT @ExpectedEmpUnpaid = E.[full_name]
    FROM [court_booking] CB
    JOIN [employee] E ON CB.[employee_id] = E.[id]
    WHERE CB.[id] = @BookingUnpaidId;

    IF @ExpectedEmpUnpaid IS NOT NULL
       AND NOT EXISTS (
            SELECT 1
            FROM #CourtBookingHistory
            WHERE [Mã booking] = @CodeUnpaid
              AND [Nhân viên]  = @ExpectedEmpUnpaid
       )
    BEGIN
        RAISERROR (N'TC03: Tên nhân viên hiển thị không khớp với bảng employee.', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * TC04: Booking "Đã hủy"
 *   - TT Thanh toán = "Đã hủy" (ưu tiên trạng thái booking)
 * ================================================================*/
PRINT N'TC04 - Booking "Đã hủy" (booking test)';
BEGIN TRY
    IF NOT EXISTS (
        SELECT 1
        FROM #CourtBookingHistory
        WHERE [Mã booking]   = @CodeCancel
          AND [TT Thanh toán] = N'Đã hủy'
    )
    BEGIN
        RAISERROR (N'TC04: Booking có status "Đã hủy" nhưng TT Thanh toán không phải "Đã hủy".', 16, 1);
    END

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * TC05: CustomerId không tồn tại
 *   - Expect: Lỗi "Không tìm thấy khách hàng với ID đã cung cấp."
 * ================================================================*/
PRINT N'TC05 - CustomerId không tồn tại';
BEGIN TRY
    DECLARE @NonExistCustomerId INT;
    SELECT @NonExistCustomerId = ISNULL(MAX(id), 0) + 1000 FROM [customer];

    EXEC sp_GetCourtBookingHistoryByCustomer @CustomerId = @NonExistCustomerId;

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * TC06: Khách không có booking (nếu tìm được)
 *   - Expect: Không lỗi, nhưng kết quả trả về 0 dòng
 * ================================================================*/
PRINT N'TC06 - Khách không có booking (nếu tồn tại)';
BEGIN TRY
    DECLARE @CustomerNoBookingId INT;

    SELECT TOP 1 @CustomerNoBookingId = C.id
    FROM [customer] C
    LEFT JOIN [court_booking] CB ON CB.[customer_id] = C.[id]
    WHERE CB.[id] IS NULL;

    IF @CustomerNoBookingId IS NULL
    BEGIN
        PRINT N'  => BỎ QUA: Hiện không có khách nào chưa từng đặt sân.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID('tempdb..#HistoryNoBooking') IS NOT NULL
            DROP TABLE #HistoryNoBooking;

        CREATE TABLE #HistoryNoBooking
        (
            [Mã booking]   NVARCHAR(50),
            [Sân]          NVARCHAR(255),
            [Loại sân]     NVARCHAR(255),
            [Khách hàng]   NVARCHAR(255),
            [Nhân viên]    NVARCHAR(255),
            [Thời gian]    NVARCHAR(MAX),
            [TT Thanh toán] NVARCHAR(50)
        );

        INSERT INTO #HistoryNoBooking
        EXEC sp_GetCourtBookingHistoryByCustomer @CustomerId = @CustomerNoBookingId;

        IF (SELECT COUNT(*) FROM #HistoryNoBooking) <> 0
        BEGIN
            RAISERROR (N'TC06: Khách không có booking nhưng SP vẫn trả về dữ liệu.', 16, 1);
        END

        PRINT N'  => KẾT QUẢ: PASS.';
    END
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * PHẦN 4: CLEANUP LẠI BOOKING TEST
 * ================================================================*/
PRINT N'=== CLEANUP LẦN CUỐI: Xóa booking test "TEST-SP-HISTORY" ===';

DELETE FROM [booking_slots]
WHERE [court_booking_id] = @BookingCancelId;

DELETE FROM [court_booking]
WHERE id = @BookingCancelId;

PRINT N'=== HOÀN THÀNH TEST sp_GetCourtBookingHistoryByCustomer ===';
PRINT N'============================================================';
