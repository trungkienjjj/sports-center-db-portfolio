USE SportsCenterDB;
GO

-- Lấy danh sách HLV/trọng tài sẵn sàng để thuê đối với 1 phiếu đặt sân
DROP PROCEDURE IF EXISTS sp_receptionist_get_trainer_referee;
GO

CREATE PROCEDURE sp_receptionist_get_trainer_referee
    @court_booking_id INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;

        -- Lấy id chi nhánh
        DECLARE @branch_id INT;
        SELECT @branch_id = c.branch_id
        FROM court_booking cb
            JOIN court c ON c.id = cb.court_id
        WHERE cb.id = @court_booking_id;

        -- 1. Lấy tất cả slot của phiếu booking
        DECLARE @slots TABLE (start_time DATETIME, end_time DATETIME);
        INSERT INTO @slots (start_time, end_time)
        SELECT start_time, end_time
        FROM booking_slots
        WHERE court_booking_id = @court_booking_id 
          AND status <> N'Đã hủy';

        -- 2. Lấy ngày đặt và thời gian slot sớm nhất
        DECLARE @booking_date DATE;
        SELECT @booking_date = booking_date
        FROM court_booking cb
        WHERE cb.id = @court_booking_id;
        
        DECLARE @earliest_slot_start DATETIME;
        SELECT @earliest_slot_start = MIN(start_time)
        FROM @slots;

        -- 3. Lấy trainer/referee sẵn sàng
        SELECT 
            e.id,
            e.full_name, 
            e.status, 
            ti.num_of_exp, 
            ti.university, 
            ti.specialization, 
            ti.price_per_hour, 
            ti.sport_type,
            ti.role
        FROM employee e
        INNER JOIN trainer_referee_info ti ON e.id = ti.employee_id
        WHERE e.branch_id = @branch_id
          AND e.status <> N'Đã nghỉ việc'
          -- Loại bỏ HLV đang nghỉ phép
          AND NOT EXISTS (
                SELECT 1
                FROM leave_request lr
                WHERE lr.creator_id = e.id
                  AND lr.approval_status = N'Đã duyệt'
                  AND @booking_date BETWEEN lr.start_date AND lr.end_date
            )
          -- Loại bỏ HLV đã được đặt trong khoảng thời gian này
          AND NOT EXISTS (
                SELECT 1
                FROM service_booking_trainer_referee sbt
                INNER JOIN service_booking_item sbi ON sbt.service_booking_item_id = sbi.id
                INNER JOIN service_booking sb ON sbi.service_booking_id = sb.id
                INNER JOIN court_booking cb ON cb.id = sb.court_booking_id
                INNER JOIN booking_slots bs2 ON cb.id = bs2.court_booking_id
                WHERE sbt.employee_id = e.id
                  AND cb.booking_date = @booking_date
                  AND bs2.status <> N'Đã hủy'
                  AND EXISTS (
                        SELECT 1
                        FROM @slots s
                        WHERE bs2.start_time < s.end_time
                          AND bs2.end_time > s.start_time
                  )
            )
          -- Chỉ lấy HLV có ca trực chứa start_time của earliest slot (thời gian bắt đầu của slot sớm nhất phải nằm trong thời gian của ca trực --> đảm bảo có HLV ở sân)
          AND EXISTS (
                SELECT 1
                FROM shift_assignment sa
                INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
                WHERE sa.employee_id = e.id
                  AND sa.status NOT IN (N'Nghỉ có phép', N'Nghỉ không phép')
                  AND ws.date = @booking_date
                  AND CAST(@earliest_slot_start AS TIME) BETWEEN ws.start_time AND ws.end_time
          );

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;