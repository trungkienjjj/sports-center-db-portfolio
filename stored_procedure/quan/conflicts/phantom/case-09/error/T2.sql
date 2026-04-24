USE SportsCenterDB;
GO

-- Lập phiếu đặt sân
DROP PROCEDURE IF EXISTS sp_create_court_booking;
GO

CREATE PROCEDURE sp_create_court_booking
    @creator INT = NULL, -- Mặc định là NULL nếu KH tự đặt
    @customer_id INT,
    @court_id INT,
    @booking_date DATE,
    @slots NVARCHAR(MAX),    -- json [{"start_time", "end_time"}]
    @by_month BIT,
    @branch_id INT,
    @type NVARCHAR(50)
AS
BEGIN
    BEGIN TRY
        DECLARE @SlotTable TABLE (
            start_time DATETIME,
            end_time DATETIME
        );
        DECLARE @court_booking_id TABLE (id INT);
        DECLARE @InsertedId INT;
        DECLARE @base_price DECIMAL(10, 2);
        DECLARE @holiday_charge DECIMAL(10, 2);
        DECLARE @weekend_charge DECIMAL(10, 2);
        DECLARE @night_charge DECIMAL(10, 2);

        BEGIN TRAN;   -- Start transaction

        -- Đọc JSON thành bảng
        INSERT INTO @SlotTable (start_time, end_time)
        SELECT start_time, end_time
        FROM OPENJSON(@slots)
        WITH (
            start_time DATETIME,
            end_time DATETIME
        );

        -- Kiểm tra trùng lịch
        IF EXISTS(
            SELECT 1
            FROM court_booking ck 
                JOIN booking_slots bs ON ck.id = bs.court_booking_id
            WHERE ck.booking_date = @booking_date 
                AND ck.court_id = @court_id
                AND ck.status <> N'Đã hủy'
                AND bs.status <> N'Đã hủy'
                AND EXISTS(SELECT 1 FROM @SlotTable WHERE bs.start_time < end_time AND bs.end_time > start_time)
        )
             THROW 50001, 'Lịch đã bị trùng, vui lòng chọn khung giờ khác.', 1;

        -- Kiểm tra phụ phí cuối tuần
        IF DATENAME(WEEKDAY, @booking_date) IN ('Saturday', 'Sunday')
        BEGIN
            SELECT @weekend_charge = weekend_booking_additional_charge
            FROM branch
            WHERE id = @branch_id;
        END
        ELSE
        BEGIN
            SET @weekend_charge = 0;
        END;

        -- Kiểm tra phụ phí ngày lễ
        IF EXISTS(
            SELECT 1
            FROM holidays 
            WHERE (@booking_date BETWEEN start_date AND end_date)
                OR (rec_month = MONTH(@booking_date) AND rec_day = DAY(@booking_date))
        )
        BEGIN
            SELECT @holiday_charge = holiday_booking_additional_charge
            FROM branch
            WHERE id = @branch_id;
        END
        ELSE
        BEGIN
            SET @holiday_charge = 0;
        END;

        -- Lấy giá cơ bản của sân
        SELECT 
            @base_price = base_hourly_price
        FROM court
        WHERE id = @court_id;

        -- Tạo phiếu đặt sân
        INSERT INTO court_booking(type, status, by_month, booked_base_price, holiday_charge, weekend_charge, customer_id, employee_id, court_id, booking_date) 
        OUTPUT INSERTED.id INTO @court_booking_id
        VALUES (@type, N'Chưa thanh toán', @by_month, @base_price, @holiday_charge, @weekend_charge, @customer_id, @creator, @court_id, @booking_date);

        -- Lấy ID vừa insert
        SELECT TOP 1 @InsertedId = id FROM @court_booking_id;

        -- Lấy thông tin phụ phí buổi tối
        SELECT @night_charge = night_booking_additional_charge
        FROM branch
        WHERE id = @branch_id;

        -- Tạo các slot ứng với phiếu
        INSERT INTO booking_slots(start_time, end_time, status, court_booking_id, night_charge)
        SELECT start_time, end_time, N'Đã đặt', @InsertedId, (CASE WHEN CAST(start_time AS TIME) >= '17:00' THEN @night_charge ELSE 0 END)
        FROM @SlotTable;
        
        COMMIT;       -- Success
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        THROW 50002, @msg, 1;
    END CATCH
END;


-- Demo lỗi
-- Kiểm tra sân 2 slot 10h
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SELECT 
    cb.id,
    cb.court_id,
    cb.booking_date,
    bs.start_time,
    bs.end_time,
    bs.status
FROM court_booking cb
JOIN booking_slots bs ON cb.id = bs.court_booking_id
WHERE cb.court_id = 2
    AND cb.booking_date = '2026-12-12'
    AND cb.status <> N'Đã hủy'
    AND bs.status <> N'Đã hủy'
    AND bs.start_time = '2026-12-12 10:00:00'
    AND bs.end_time = '2026-12-12 11:00:00';

-- Lễ tân tạo booking mới cho customer 2, sân 2, slot 10-11h
DECLARE @json2 NVARCHAR(MAX) = N'[
    {
        "start_time": "2026-12-12T10:00:00",
        "end_time":   "2026-12-12T11:00:00"
    }
]';

EXEC sp_create_court_booking
        @creator = 1, -- employee_id của lễ tân
        @customer_id = 2,
        @court_id = 2,
        @booking_date = '2026-12-12',
        @slots = @json2,
        @by_month = 0,
        @branch_id = 1,
        @type = N'Trực tiếp';