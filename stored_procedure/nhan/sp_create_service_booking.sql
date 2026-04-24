USE SportsCenterDB;
GO

-- Lập phiếu đặt dịch vụ
-- Với các dịch vụ như đặt vợt, tủ khóa, áo bib: đặt và giữ từ start_time (slot đầu tiên) đến end_time (slot cuối cùng); tính tồn kho dựa trên công thức (current_stock - stock đã đặt tại thời điểm đặt)
--SELECT
--    bs.current_stock
--      - ISNULL((
--          SELECT SUM(s.quantity)
--          FROM booking_service s
--              JOIN booking b ON s.booking_id = b.id
--          WHERE s.service_id = @service_id
--            AND b.branch_id = @branch_id
--            AND b.status <> N'Đã hủy'
--            AND (
--                 s.start_time < @end_time
--             AND s.end_time   > @start_time
--            )
--      ), 0) AS available
--FROM branch_service bs
--WHERE bs.service_id = @service_id
--  AND bs.branch_id  = @branch_id;
-- Với các dịch vụ như phòng tắm: cho đặt thoải mái (do vào tắm cái ra)
-- Với HLV, trọng tài: với mỗi booking_slots tạo 1 service_booking_item
-- Với nước uống: sử dụng global stock: khi đặt thì trừ, hủy thì cộng lại
-- Tóm lại:
-- Time-based stock ⏱️
--  Limited items that are booked for specific time slots.
--  Examples: rackets, lockers, bibs.
--  Stock is reserved per slot. Availability = total quantity − sum of overlapping bookings.
-- Consumable/global stock 🍹
--  Items that are used/consumed immediately and tracked globally.
--  Examples: water bottles, towels.
--  Booking reduces stock; canceling restores it. No slot association needed.
-- Unlimited stock ♾️
--  Items/services that do not require tracking quantity.
--  Examples: showers (assume enough capacity, or no need to block), open-access facilities.
-- Special calculation / per-slot stock 👩‍🏫⚖️
--  Trainers, referees, or any staff where pricing or availability depends on the number of slots booked.
--  Each slot may generate a separate service booking item.
--  Availability = number of trainers/referees free per slot.
-- Vậy nên thêm stock_type vào bảng service để biết như nào mà tính.
-- Note: Vậy sau khi thuê các dụng cụ (có tồn kho), thì xài xong phải trả cho 1 chỗ nào đó, và nhân viên chỗ đó có nhiệm vụ cộng lại stock.

DROP PROCEDURE IF EXISTS sp_create_service_booking;
GO

CREATE PROCEDURE sp_create_service_booking
    @court_booking_id INT,
    @employee_id INT = NULL,      -- Receptionist creating this booking, NULL if user books
    @items NVARCHAR(MAX)          -- JSON [{"branch_service_id":1,"quantity":1,"start_time":"2025-12-05T10:00:00","end_time":"2025-12-05T11:00:00","by_month":0,"employee_id":5}, ...]
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;  -- Start transaction

        -- 1. Tạo service_booking
        DECLARE @service_booking_id INT;
        INSERT INTO service_booking(court_booking_id, employee_id, status)
        VALUES (@court_booking_id, @employee_id, N'Chưa thanh toán');
        SET @service_booking_id = SCOPE_IDENTITY();

        -- 2. Parse items JSON
        DECLARE @ItemTable TABLE (
            branch_service_id INT,
            quantity INT,
            start_time DATETIME,
            end_time DATETIME,
            by_month BIT,
            employee_id INT
        );

        INSERT INTO @ItemTable(branch_service_id, quantity, start_time, end_time, by_month, employee_id)
        SELECT branch_service_id, quantity, start_time, end_time, by_month, employee_id
        FROM OPENJSON(@items)
        WITH (
            branch_service_id INT,
            quantity INT,
            start_time DATETIME,
            end_time DATETIME,
            by_month BIT,
            employee_id INT
        );

        -- 3. Xử lý từng item
        DECLARE @branch_service_id INT,
                @quantity INT,
                @start_time DATETIME,
                @end_time DATETIME,
                @unit_price DECIMAL(10,2),
                @service_stock_type NVARCHAR(100),
                @by_month BIT,
                @emp_id INT,
                @current_stock INT,
                @min_stock_threshold INT,
                @booking_date DATE,
                @booked_qty INT;

        SELECT @booking_date = booking_date
        FROM court_booking
        WHERE id = @court_booking_id;

        DECLARE item_cursor CURSOR FOR
            SELECT branch_service_id, quantity, start_time, end_time, by_month, employee_id
            FROM @ItemTable;

        OPEN item_cursor;
        FETCH NEXT FROM item_cursor INTO @branch_service_id, @quantity, @start_time, @end_time, @by_month, @emp_id;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Lấy thông tin dịch vụ
            SELECT @unit_price = bs.unit_price,
                   @service_stock_type = s.stock_type,
                   @current_stock = bs.current_stock,
                   @min_stock_threshold = bs.min_stock_threshold
            FROM branch_service bs
                JOIN service s ON bs.service_id = s.id
            WHERE bs.id = @branch_service_id;

            -- ===== Kiểm tra tồn kho dựa trên loại =====
            IF @service_stock_type = 'theo_thoi_gian'
            BEGIN
                SELECT @booked_qty = ISNULL(SUM(sbi.quantity),0)
                FROM service_booking_item sbi
                    JOIN service_booking sb ON sbi.service_booking_id = sb.id
                    JOIN court_booking cb ON sb.court_booking_id = cb.id
                WHERE sbi.branch_service_id = @branch_service_id
                  AND cb.booking_date = @booking_date
                  AND NOT (sbi.end_time <= @start_time OR sbi.start_time >= @end_time);

                IF @current_stock - (@booked_qty + @quantity) <= @min_stock_threshold
                    THROW 50001, 'Không đủ số lượng để đặt', 1;
            END
            ELSE IF @service_stock_type = 'tieu_hao'
            BEGIN
                IF @current_stock - @quantity <= @min_stock_threshold
                    THROW 50001, 'Không đủ số lượng để đặt', 1;

                -- Trừ ngay khỏi tồn kho toàn cục (có thể xảy ra lost update)
                UPDATE branch_service
                SET current_stock = @current_stock - @quantity
                WHERE id = @branch_service_id;
            END

            -- 4. Insert service_booking_item
            INSERT INTO service_booking_item(
                service_booking_id, branch_service_id, quantity, start_time, end_time, status, booked_unit_price, by_month
            )
            VALUES (
                @service_booking_id, @branch_service_id, @quantity, @start_time, @end_time, N'Đã đặt', @unit_price, @by_month
            );

            DECLARE @service_booking_item_id INT = SCOPE_IDENTITY();

            -- 5. Xử lý HLV / Trọng tài nếu có
            IF @service_stock_type IN ('hlv_trong_tai')
            BEGIN
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

                -- 2. Lấy thời gian slot sớm nhất
                DECLARE @earliest_slot_start DATETIME;
                SELECT @earliest_slot_start = MIN(start_time)
                FROM @slots;

                -- 3. Kiểm tra
                IF NOT EXISTS (
                    SELECT 1
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
                      )
                      AND e.id = @emp_id
                )
                    THROW 50003, 'HLV/Trọng tài không khả dụng cho khoảng thời gian này', 1;

                -- Assign trainer/referee
                INSERT INTO service_booking_trainer_referee(service_booking_item_id, employee_id, booked_price)
                SELECT @service_booking_item_id, @emp_id, ISNULL(ti.price_per_hour, 0)
                FROM trainer_referee_info ti WHERE ti.employee_id = @emp_id;
            END

            FETCH NEXT FROM item_cursor INTO @branch_service_id, @quantity, @start_time, @end_time, @by_month, @emp_id;
        END

        CLOSE item_cursor;
        DEALLOCATE item_cursor;

        COMMIT; -- Success
        SELECT @service_booking_id AS service_booking_id;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        THROW 50002, @msg, 1;
    END CATCH
END;