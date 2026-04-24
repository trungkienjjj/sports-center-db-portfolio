USE SportsCenterDB;
GO

-- Lấy thông tin về các booking_slots (đã đặt) của một sân trong 1 ngày nào đó
DROP PROCEDURE IF EXISTS sp_receptionist_get_booking_slots_of_court;
GO

CREATE PROCEDURE sp_receptionist_get_booking_slots_of_court
    @court_id INT,
    @date DATE
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;   -- Start transaction

        SELECT bs.id, bs.start_time, bs.end_time, bs.status, ct.full_name AS customer_name, ct.phone_number AS customer_phone_number
        FROM court_booking ck 
            JOIN booking_slots bs ON ck.id = bs.court_booking_id
            JOIN customer ct ON ct.id = ck.customer_id
        WHERE ck.court_id = @court_id 
            AND ck.booking_date = @date 
            AND ck.status <> N'Đã hủy'
            AND bs.status <> N'Đã hủy';
        
        COMMIT;       -- Success
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;