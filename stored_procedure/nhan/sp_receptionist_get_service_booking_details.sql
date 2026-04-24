USE SportsCenterDB;
GO

-- Lấy thông tin chi tiết của 1 phiếu đặt dịch vụ
DROP PROCEDURE IF EXISTS sp_receptionist_get_service_booking_details;
GO

CREATE PROCEDURE sp_receptionist_get_service_booking_details
    @service_booking_id INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. List of service_booking_item
    SELECT 
        sbi.id AS service_booking_item_id,
        sbi.service_booking_id,
        sbi.branch_service_id,
        s.name AS service_name,
        bs.unit_price,
        sbi.quantity,
        sbi.start_time,
        sbi.end_time,
        sbi.status,
        sbi.booked_unit_price,
        sbi.by_month
    FROM service_booking_item sbi
    INNER JOIN branch_service bs ON sbi.branch_service_id = bs.id
    INNER JOIN service s ON bs.service_id = s.id
    WHERE sbi.service_booking_id = @service_booking_id;

    -- 2. Trainer / referee assigned to items
    SELECT
        sbtr.service_booking_item_id,
        sbtr.employee_id,
        e.full_name,
        tri.role,
        sbtr.booked_price
    FROM service_booking_trainer_referee sbtr
    INNER JOIN employee e ON sbtr.employee_id = e.id
    INNER JOIN trainer_referee_info tri ON sbtr.employee_id = tri.employee_id
    WHERE sbtr.service_booking_item_id IN (
        SELECT id FROM service_booking_item WHERE service_booking_id = @service_booking_id
    );
END;
GO