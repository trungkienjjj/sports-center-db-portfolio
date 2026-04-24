USE SportsCenterDB;
GO

-- Đổi giờ/sân (không bị trùng lịch với chính NÓ - tức là slots mới có thể chồng lắp với slots cũ)
DROP PROCEDURE IF EXISTS sp_receptionist_update_court_booking;
GO

CREATE PROCEDURE sp_receptionist_update_court_booking
    @booking_id INT,
    @new_court_id INT,
    @new_booking_date DATE,
    @new_slots NVARCHAR(MAX),      -- json
    @branch_id INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- ======== TEMP TABLES ==========
        DECLARE @SlotTable TABLE (
            start_time DATETIME,
            end_time DATETIME
        );

        DECLARE @base_price DECIMAL(10,2);
        DECLARE @holiday_charge DECIMAL(10,2) = 0;
        DECLARE @weekend_charge DECIMAL(10,2) = 0;
        DECLARE @night_charge DECIMAL(10,2) = 0;

        DECLARE @oldCourtId INT;
        DECLARE @oldDate DATE;
        DECLARE @by_month BIT;

        -- ======== READ EXISTING BOOKING ==========
        SELECT 
            @oldCourtId = court_id,
            @oldDate = booking_date,
            @by_month = by_month
        FROM court_booking
        WHERE id = @booking_id;

        IF @oldCourtId IS NULL
            THROW 50000, 'Phiếu đặt sân không tồn tại.', 1;

        -- ======== PARSE SLOT JSON ==========
        INSERT INTO @SlotTable(start_time, end_time)
        SELECT start_time, end_time
        FROM OPENJSON(@new_slots)
        WITH(start_time DATETIME, end_time DATETIME);

        -- ======== CHECK OVERLAP EXCEPT ITSELF ==========
        IF EXISTS(
            SELECT 1
            FROM court_booking ck
                JOIN booking_slots bs ON ck.id = bs.court_booking_id
            WHERE ck.booking_date = @new_booking_date
                AND ck.court_id = @new_court_id
                AND ck.id <> @booking_id
                AND ck.status <> N'Đã hủy'
                AND bs.status <> N'Đã hủy'
                AND EXISTS(SELECT 1 FROM @SlotTable t
                    WHERE bs.start_time <= t.end_time
                      AND bs.end_time >= t.start_time)
        )
            THROW 50001, N'Lịch đã bị trùng, vui lòng chọn khung giờ khác.', 1;

        -- ======== WEEKEND CHARGE ==========
        IF DATENAME(WEEKDAY, @new_booking_date) IN ('Saturday', 'Sunday')
            SELECT @weekend_charge = weekend_booking_additional_charge
            FROM branch WHERE id = @branch_id;

        -- ======== HOLIDAY CHARGE ==========
        IF EXISTS(
            SELECT 1 FROM holidays
            WHERE (@new_booking_date BETWEEN start_date AND end_date)
               OR (rec_month = MONTH(@new_booking_date)
               AND rec_day = DAY(@new_booking_date))
        )
            SELECT @holiday_charge = holiday_booking_additional_charge
            FROM branch WHERE id = @branch_id;

        -- ======== BASE PRICE OF COURT ==========
        SELECT @base_price = base_hourly_price
        FROM court WHERE id = @new_court_id;

        IF @base_price IS NULL
            THROW 50002, 'Sân không tồn tại.', 1;

        -- ======== NIGHT CHARGE ==========
        SELECT @night_charge = night_booking_additional_charge
        FROM branch WHERE id = @branch_id;

		WAITFOR DELAY '00:00:20'

        -- ======== UPDATE court_booking (court/date/charges) ==========
        UPDATE court_booking
        SET court_id = @new_court_id,
            booking_date = @new_booking_date,
            booked_base_price = @base_price,
            holiday_charge = @holiday_charge,
            weekend_charge = @weekend_charge
        WHERE id = @booking_id;

        -- =====================================================
        -- KEEP EXISTING SLOTS IF THEY APPEAR IN NEW SLOTS
        -- =====================================================

        -- Existing active slots for this booking
        DECLARE @ExistingSlots TABLE (
            start_time DATETIME,
            end_time DATETIME
        );

        INSERT INTO @ExistingSlots(start_time, end_time)
        SELECT start_time, end_time
        FROM booking_slots
        WHERE court_booking_id = @booking_id
          AND status <> N'Đã hủy';

        -- Slots to KEEP = intersection between existing and new
        DECLARE @KeepSlots TABLE (
            start_time DATETIME,
            end_time DATETIME
        );

        INSERT INTO @KeepSlots(start_time, end_time)
        SELECT e.start_time, e.end_time
        FROM @ExistingSlots e
        INNER JOIN @SlotTable n
            ON e.start_time = n.start_time
           AND e.end_time = n.end_time;

        -- =====================================================
        -- SOFT DELETE OLD SLOTS EXCEPT KEPT ONES
        -- =====================================================
        UPDATE booking_slots
        SET status = N'Đã hủy'
        WHERE court_booking_id = @booking_id
          AND status <> N'Đã hủy'
          AND NOT EXISTS (
                SELECT 1 FROM @KeepSlots k
                WHERE k.start_time = booking_slots.start_time
                  AND k.end_time = booking_slots.end_time
          );

        -- =====================================================
        -- INSERT NEW SLOTS EXCEPT THOSE KEPT
        -- =====================================================
        INSERT INTO booking_slots(start_time, end_time, status, court_booking_id, night_charge)
        SELECT 
            n.start_time,
            n.end_time,
            N'Đã đặt',
            @booking_id,
            CASE WHEN CAST(n.start_time AS TIME) >= '17:00' THEN @night_charge ELSE 0 END
        FROM @SlotTable n
        WHERE NOT EXISTS (
            SELECT 1 FROM @KeepSlots k
            WHERE k.start_time = n.start_time
              AND k.end_time = n.end_time
        );

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        THROW;
    END CATCH
END;


-- Reset dữ liệu demo
DELETE FROM court_booking WHERE customer_id=1
DELETE FROM court_booking WHERE customer_id=2

-- Tạo 1 booking ban đầu cho customer 1, sân 1, ngày 2026-12-12, slot 9-10h
DECLARE @json1 NVARCHAR(MAX) = N'[
    {
        "start_time": "2026-12-12T09:00:00",
        "end_time":   "2026-12-12T10:00:00"
    }
]';
EXEC sp_create_court_booking
    @creator = NULL,
    @customer_id = 1,
    @court_id = 1,
    @booking_date = '2026-12-12',
    @slots = @json1,
    @by_month = 0,
    @branch_id = 1,
    @type = N'Online';
-- Tắt ràng buộc toàn vẹn để lỗi xảy ra
DISABLE TRIGGER TG_R1403_NoCourtOverlap ON booking_slots;

-- Kiểm tra các phiếu đặt sân
SELECT 
    cb.id AS booking_id,
    cb.court_id,
	cb.customer_id,
    cb.booking_date,
    bs.start_time,
    bs.end_time,
    bs.status
FROM court_booking cb
JOIN booking_slots bs ON cb.id = bs.court_booking_id
ORDER BY cb.id DESC;


-- Đổi sân
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ
DECLARE @booking_id INT = 25;
DECLARE @new_slots NVARCHAR(MAX) = N'[
    {
        "start_time": "2026-12-12T10:00:00",
        "end_time":   "2026-12-12T11:00:00"
    }
]';

EXEC sp_receptionist_update_court_booking
    @booking_id = @booking_id,
    @new_court_id = 2,
    @new_booking_date = '2026-12-12',
    @new_slots = @new_slots,
    @branch_id = 1;

-- Kiểm tra sau khi đổi
SELECT 
    cb.id AS booking_id,
    cb.court_id,
	cb.customer_id,
    cb.booking_date,
    bs.start_time,
    bs.end_time,
    bs.status
FROM court_booking cb
JOIN booking_slots bs ON cb.id = bs.court_booking_id
ORDER BY cb.id DESC;