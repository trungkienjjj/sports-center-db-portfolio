USE SportsCenterDB;
GO

-- Tính giá tiền của các booking_slots trong 1 ngày nào đó của 1 sân nào đó
DROP PROCEDURE IF EXISTS sp_receptionist_calculate_slots_price;
GO

CREATE PROCEDURE sp_receptionist_calculate_slots_price
    @court_id INT,
    @date DATE,
    @slots NVARCHAR(MAX)    -- JSON [{"start_time":"2025-12-05T10:00:00","end_time":"2025-12-05T11:00:00"}, ...]
AS
BEGIN
    BEGIN TRY
        DECLARE @SlotTable TABLE (
            start_time DATETIME,
            end_time DATETIME,
            base_price DECIMAL(10,2),
            holiday_charge DECIMAL(10,2),
            weekend_charge DECIMAL(10,2),
            night_charge DECIMAL(10,2),
            total_price DECIMAL(18,4)
        );

        DECLARE @branch_id INT;
        DECLARE @base_price DECIMAL(10,2);
        DECLARE @holiday_charge DECIMAL(10,2);
        DECLARE @weekend_charge DECIMAL(10,2);
        DECLARE @night_charge DECIMAL(10,2);

        -- Lấy branch_id và giá cơ bản của sân
        SELECT @branch_id = branch_id, @base_price = base_hourly_price
        FROM court
        WHERE id = @court_id;

        -- Parse JSON thành bảng
        INSERT INTO @SlotTable (start_time, end_time)
        SELECT start_time, end_time
        FROM OPENJSON(@slots)
        WITH (
            start_time DATETIME,
            end_time DATETIME
        );

        -- Phụ phí cuối tuần
        IF DATENAME(WEEKDAY, @date) IN ('Saturday','Sunday')
            SELECT @weekend_charge = weekend_booking_additional_charge
            FROM branch
            WHERE id = @branch_id;
        ELSE
            SET @weekend_charge = 0;

        -- Phụ phí ngày lễ
        IF EXISTS(
            SELECT 1 
            FROM holidays 
            WHERE (@date BETWEEN start_date AND end_date)
               OR (rec_month = MONTH(@date) AND rec_day = DAY(@date))
        )
            SELECT @holiday_charge = holiday_booking_additional_charge
            FROM branch
            WHERE id = @branch_id;
        ELSE
            SET @holiday_charge = 0;

        -- Phụ phí ban đêm
        SELECT @night_charge = night_booking_additional_charge
        FROM branch
        WHERE id = @branch_id;

        -- Tính tiền cho từng slot
        UPDATE @SlotTable
        SET 
            base_price = @base_price,
            weekend_charge = @weekend_charge,
            holiday_charge = @holiday_charge,
            night_charge = CASE WHEN CAST(start_time AS TIME) >= '17:00' THEN @night_charge ELSE 0 END,
            total_price = @base_price * (1 + @holiday_charge + @weekend_charge + CASE WHEN CAST(start_time AS TIME) >= '17:00' THEN @night_charge ELSE 0 END);

        -- Kết quả
        SELECT start_time, end_time, base_price, holiday_charge, weekend_charge, night_charge, total_price
        FROM @SlotTable;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;
GO