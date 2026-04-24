USE SportsCenterDB;
GO

-- Xem các phiếu đặt sân của một khách hàng
DROP PROCEDURE IF EXISTS sp_receptionist_get_customer_court_bookings;
GO

CREATE PROCEDURE sp_receptionist_get_customer_court_bookings
    @customer_id INT,
    @branch_id INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;   -- Start transaction

        SELECT cb.id, cb.status, cb.booking_date, cb.by_month, c.name as court_name, ct.name as court_type,
            SUM(cb.booked_base_price * (1 + cb.holiday_charge + cb.weekend_charge + bs.night_charge)) AS total_price,
            (
                SELECT 
                    bs.id AS slot_id,
                    bs.start_time,
                    bs.end_time,
                    bs.status,
                    bs.night_charge
                FROM booking_slots bs
                WHERE bs.court_booking_id = cb.id AND bs.status <> N'Đã hủy'
                FOR JSON PATH
            ) AS slots
        FROM court_booking cb
            JOIN court c ON c.id = cb.court_id
            JOIN court_type ct ON c.court_type_id = ct.id
            JOIN booking_slots bs ON cb.id = bs.court_booking_id
        WHERE cb.customer_id = @customer_id AND c.branch_id = @branch_id AND cb.status <> N'Đã hủy'
        GROUP BY cb.id, cb.status, cb.booking_date, cb.by_month, c.name, ct.name;
        
        COMMIT;       -- Success
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;