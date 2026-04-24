USE SportsCenterDB;
GO

-- Lấy các phiếu đặt dịch vụ của 1 phiếu đặt sân
DROP PROCEDURE IF EXISTS sp_receptionist_get_service_booking_info;
GO

CREATE PROCEDURE sp_receptionist_get_service_booking_info
    @court_booking_id INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 
        sb.id AS service_booking_id,
        sb.court_booking_id,
        sb.employee_id AS receptionist_id,
        e.full_name AS receptionist_name,
        sb.status,
        sb.created_at
    FROM service_booking sb
    LEFT JOIN employee e ON sb.employee_id = e.id
    WHERE sb.court_booking_id = @court_booking_id;
END;
GO