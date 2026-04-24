USE SportsCenterDB;
GO

-- =============================================
-- 10.1. SP_GetInvoiceDetails
-- Mô tả: Xem thông tin đặt sân (CHỈ HIỂN THỊ - KHÔNG TÍNH TOÁN)
-- Tham số: @CourtBookingId (Mã đặt sân)
-- Trả về: Tên khách hàng, Tên cơ sở, Tên sân, Khung giờ, Giá sân, Giá dịch vụ
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetInvoiceDetails
    @CourtBookingId INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Kiểm tra mã đặt sân tồn tại
    IF NOT EXISTS (SELECT 1 FROM court_booking WHERE id = @CourtBookingId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Mã đặt sân không tồn tại' AS Message;
        RETURN;
    END
    -- Trả về thông tin cơ bản (1 result set duy nhất)
    SELECT 
        -- Thông tin khách hàng
        cust.full_name AS CustomerName,
        -- Thông tin cơ sở
        b.[name] AS BranchName,
        -- Thông tin sân
        c.[name] AS CourtName,
        -- Khung giờ (VD: "12h - 14h")
        STRING_AGG(
            CONCAT(
                FORMAT(bs.start_time, 'HH'), 'h', 
                ' - ', 
                FORMAT(bs.end_time, 'HH'), 'h'
            ), 
            ', '
        ) WITHIN GROUP (ORDER BY bs.start_time) AS TimeSlots,
        -- Giá sân (chưa tính tổng)
        cb.booked_base_price AS CourtPrice,
        -- Giá dịch vụ (nếu có)
        ISNULL(
            (SELECT SUM(sbi.quantity * sbi.booked_unit_price)
             FROM service_booking sb
             INNER JOIN service_booking_item sbi ON sb.id = sbi.service_booking_id
             WHERE sb.court_booking_id = cb.id), 
            0
        ) AS ServicePrice
    FROM court_booking cb
    INNER JOIN customer cust ON cb.customer_id = cust.id
    INNER JOIN court c ON cb.court_id = c.id
    INNER JOIN branch b ON c.branch_id = b.id
    INNER JOIN booking_slots bs ON cb.id = bs.court_booking_id
    WHERE cb.id = @CourtBookingId
    GROUP BY 
        cust.full_name,
        b.[name],
        c.[name],
        cb.booked_base_price,
        cb.id;
END
GO

-- =============================================
-- 10.2. SP_GetServiceBookingDetails
-- Mô tả: Xem danh sách dịch vụ CÓ THỂ đặt thêm cho đặt sân (ĐỦ THÔNG TIN CHO 10.3)
-- Tham số: @CourtBookingId (Mã đặt sân)
-- Trả về: BranchServiceId, ServiceName, UnitPrice, CurrentStock, RentalType, StockType
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetServiceBookingDetails
    @CourtBookingId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Kiểm tra mã đặt sân tồn tại
    IF NOT EXISTS (SELECT 1 FROM court_booking WHERE id = @CourtBookingId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Mã đặt sân không tồn tại' AS Message;
        RETURN;
    END
    
    -- Lấy branch_id từ court_booking
    DECLARE @BranchId INT;
    SELECT @BranchId = c.branch_id
    FROM court_booking cb
    INNER JOIN court c ON cb.court_id = c.id
    WHERE cb.id = @CourtBookingId;
    
    -- Trả về danh sách dịch vụ CÓ THỂ đặt thêm tại chi nhánh (1 result set duy nhất)
    SELECT 
        bs.id AS BranchServiceId, -- ID để gọi sp_AddServicesToCourtBooking
        s.[name] AS ServiceName, -- Tên dịch vụ
        s.[unit] AS Unit, -- Đơn vị (Cái, Người, Chai...)
        s.rental_type AS RentalType, -- Theo giờ / Theo lần
        s.stock_type AS StockType, -- theo_thoi_gian / tieu_hao / khong_gioi_han / hlv_trong_tai
        bs.unit_price AS UnitPrice, -- Giá đơn vị
        bs.current_stock AS CurrentStock, -- Tồn kho hiện tại
        bs.[status] AS AvailabilityStatus -- Còn / Hết
    FROM branch_service bs
    INNER JOIN [service] s ON bs.service_id = s.id
    WHERE bs.branch_id = @BranchId
        AND bs.[status] = N'Còn' -- Chỉ hiển thị dịch vụ còn hàng
    ORDER BY s.[name];
END
GO

-- =============================================
--10.3 sp_AddServicesToCourtBooking
-- Mô tả: Thêm MỘT dịch vụ vào đặt sân (Backend/Frontend dùng vòng lặp)
-- Tham số: 
--   @CourtBookingId - Mã đặt sân
--   @BranchServiceId - ID dịch vụ
--   @Quantity - Số lượng
--   @StartTime, @EndTime - Thời gian sử dụng
--   @ByMonth - Thuê theo tháng (0/1)
-- Trả về: Success/Error message
-- =============================================
CREATE OR ALTER PROCEDURE sp_AddServicesToCourtBooking
    @CourtBookingId INT,
    @BranchServiceId INT,
    @Quantity INT,
    @StartTime DATETIME,
    @EndTime DATETIME,
    @ByMonth BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Kiểm tra mã đặt sân tồn tại
        IF NOT EXISTS (SELECT 1 FROM court_booking WHERE id = @CourtBookingId)
        BEGIN
            SELECT 
                0 AS Success,
                N'Mã đặt sân không tồn tại' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Kiểm tra dịch vụ hợp lệ
        IF NOT EXISTS (
            SELECT 1 
            FROM branch_service 
            WHERE id = @BranchServiceId 
              AND [status] = N'Còn'
        )
        BEGIN
            SELECT 
                0 AS Success,
                N'Dịch vụ không hợp lệ hoặc đã hết hàng' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Kiểm tra tồn kho đủ (nếu là loại dịch vụ có tồn kho)
        DECLARE @CurrentStock INT;
        DECLARE @StockType NVARCHAR(100);
        
        SELECT 
            @CurrentStock = bs.current_stock,
            @StockType = s.stock_type
        FROM branch_service bs
        INNER JOIN [service] s ON bs.service_id = s.id
        WHERE bs.id = @BranchServiceId;
        
        IF @StockType IN (N'tieu_hao', N'theo_thoi_gian') AND @Quantity > @CurrentStock
        BEGIN
            SELECT 
                0 AS Success,
                N'Số lượng đặt vượt quá tồn kho hiện tại' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Kiểm tra xem đã có service_booking cho court_booking này chưa
        DECLARE @ServiceBookingId INT;
        SELECT @ServiceBookingId = id 
        FROM service_booking 
        WHERE court_booking_id = @CourtBookingId;
        
        -- Nếu chưa có, tạo mới service_booking
        IF @ServiceBookingId IS NULL
        BEGIN
            INSERT INTO service_booking (created_at, [status], court_booking_id, employee_id)
            VALUES (GETDATE(), N'Chưa thanh toán', @CourtBookingId, NULL);
            
            SET @ServiceBookingId = SCOPE_IDENTITY();
        END
        
        -- Lấy giá hiện tại của dịch vụ
        DECLARE @UnitPrice DECIMAL(10, 2);
        SELECT @UnitPrice = unit_price 
        FROM branch_service 
        WHERE id = @BranchServiceId;
        
        -- Thêm dịch vụ vào service_booking_item
        INSERT INTO service_booking_item (
            created_at,
            quantity,
            start_time,
            end_time,
            by_month,
            [status],
            booked_unit_price,
            service_booking_id,
            branch_service_id
        )
        VALUES (
            GETDATE(),
            @Quantity,
            @StartTime,
            @EndTime,
            @ByMonth,
            N'Đã đặt',
            @UnitPrice,
            @ServiceBookingId,
            @BranchServiceId
        );
        
        DECLARE @ServiceBookingItemId INT = SCOPE_IDENTITY();
        
        -- Cập nhật tồn kho (chỉ với loại dịch vụ có tồn kho)
        IF @StockType IN (N'tieu_hao', N'theo_thoi_gian')
        BEGIN
            UPDATE branch_service
            SET current_stock = current_stock - @Quantity
            WHERE id = @BranchServiceId;
        END
        
        COMMIT TRANSACTION;
        
        -- Trả về thông báo thành công
        SELECT 
            1 AS Success,
            N'Đã thêm dịch vụ vào đặt sân thành công' AS Message,
            @ServiceBookingId AS ServiceBookingId,
            @ServiceBookingItemId AS ServiceBookingItemId;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        
        SELECT 
            0 AS Success,
            N'Lỗi: ' + ERROR_MESSAGE() AS Message;
    END CATCH
END
GO

-- =============================================
-- 10.4. SP_CalculateInvoice
-- Mô tả: Tính toán hóa đơn cho đặt sân và TẠO HÓA ĐƠN
-- Tham số: 
--   @CourtBookingId - Mã đặt sân
--   @DiscountPolicyIds - JSON array các mã khuyến mãi (ví dụ: '[1,2,3]')
--   @PaymentMethod - Phương thức thanh toán
--   @EmployeeId - ID nhân viên thu ngân (có thể NULL nếu đặt online)
-- Trả về: Tiền sân, Tiền dịch vụ, Tiền giảm giá, Tổng thanh toán, InvoiceId
-- =============================================
CREATE OR ALTER PROCEDURE SP_CalculateInvoice
    @CourtBookingId INT,
    @DiscountPolicyIds NVARCHAR(MAX) = NULL, -- JSON array: '[1,2,3]'
    @PaymentMethod NVARCHAR(50),
    @EmployeeId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Kiểm tra mã đặt sân tồn tại
    IF NOT EXISTS (SELECT 1 FROM court_booking WHERE id = @CourtBookingId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Mã đặt sân không tồn tại' AS Message;
        RETURN;
    END
    
    -- Khai báo biến để lưu trữ các giá trị tính toán
    DECLARE @CourtPrice DECIMAL(10, 2) = 0;
    DECLARE @ServicePrice DECIMAL(10, 2) = 0;
    DECLARE @SubTotal DECIMAL(10, 2) = 0;
    DECLARE @FixedDiscountTotal DECIMAL(10, 2) = 0;
    DECLARE @PercentDiscountTotal DECIMAL(10, 2) = 0;
    DECLARE @FinalTotal DECIMAL(10, 2) = 0;
    DECLARE @InvoiceId INT;
    
    -- 1. Tính TIỀN SÂN (Base Price × (1 + weekend% + holiday% + night%))
    SELECT 
        @CourtPrice = 
            cb.booked_base_price * (1 + ISNULL(cb.holiday_charge, 0) + ISNULL(cb.weekend_charge, 0) + ISNULL(SUM(bs.night_charge), 0))
    FROM court_booking cb
    INNER JOIN booking_slots bs ON cb.id = bs.court_booking_id
    WHERE cb.id = @CourtBookingId
    GROUP BY cb.booked_base_price, cb.holiday_charge, cb.weekend_charge;
    
    -- 2. Tính TIỀN DỊCH VỤ (nếu có đặt kèm theo)
    SELECT @ServicePrice = ISNULL(SUM(sbi.quantity * sbi.booked_unit_price), 0)
    FROM service_booking sb
    INNER JOIN service_booking_item sbi ON sb.id = sbi.service_booking_id
    WHERE sb.court_booking_id = @CourtBookingId;
    
    -- 3. Tính TỔNG TẠM TÍNH (Tiền sân + Tiền dịch vụ)
    SET @SubTotal = @CourtPrice + @ServicePrice;
    
    -- 4. Tính TIỀN GIẢM GIÁ (nếu có khuyến mãi)
    IF @DiscountPolicyIds IS NOT NULL AND @DiscountPolicyIds != '[]'
    BEGIN
        -- Tạo bảng tạm chứa các discount policy
        DECLARE @DiscountTable TABLE (
            DiscountPolicyId INT,
            DiscountType NVARCHAR(50),
            DiscountValue DECIMAL(10, 2)
        );
        
        -- Parse JSON và lấy thông tin discount policy
        INSERT INTO @DiscountTable (DiscountPolicyId, DiscountType, DiscountValue)
        SELECT 
            dp.id,
            dp.[type],
            dp.discount_value
        FROM discount_policy dp
        INNER JOIN OPENJSON(@DiscountPolicyIds) AS json_ids
            ON dp.id = TRY_CAST(json_ids.[value] AS INT)
        WHERE dp.id IS NOT NULL;
        
        -- Bước 1: Áp dụng GIẢM GIÁ CỐ ĐỊNH trước
        SELECT @FixedDiscountTotal = ISNULL(SUM(DiscountValue), 0)
        FROM @DiscountTable
        WHERE DiscountType = N'Giảm giá cố định';
        
        -- Trừ tiền giảm cố định khỏi SubTotal
        DECLARE @AfterFixedDiscount DECIMAL(10, 2) = @SubTotal - @FixedDiscountTotal;
        IF @AfterFixedDiscount < 0 SET @AfterFixedDiscount = 0;
        
        -- Bước 2: Áp dụng GIẢM THEO % trên số tiền đã giảm cố định
        DECLARE @TotalPercentRate DECIMAL(10, 4) = 0;
        
        SELECT @TotalPercentRate = ISNULL(SUM(DiscountValue), 0)
        FROM @DiscountTable
        WHERE DiscountType = N'Giảm theo phần trăm';
        
        -- Tính tiền giảm theo %
        SET @PercentDiscountTotal = @AfterFixedDiscount * @TotalPercentRate;
    END
    
    -- 5. Tính TỔNG THANH TOÁN (Tổng tạm tính - Giảm cố định - Giảm %)
    SET @FinalTotal = @SubTotal - @FixedDiscountTotal - @PercentDiscountTotal;
    IF @FinalTotal < 0 SET @FinalTotal = 0;
    
    -- 6. TẠO HÓA ĐƠN trong bảng invoice
    INSERT INTO invoice (
        created_at,
        total_amount,
        payment_method,
        [status],
        court_booking_id,
        employee_id
    )
    VALUES (
        GETDATE(),
        @FinalTotal,
        @PaymentMethod,
        N'Đã thanh toán',
        @CourtBookingId,
        @EmployeeId
    );
    
    SET @InvoiceId = SCOPE_IDENTITY();
    
    -- 7. Lưu discount policies vào bảng invoice_discount
    IF @DiscountPolicyIds IS NOT NULL AND @DiscountPolicyIds != '[]'
    BEGIN
        INSERT INTO invoice_discount (invoice_id, discount_policy_id)
        SELECT 
            @InvoiceId,
            TRY_CAST(json_ids.[value] AS INT)
        FROM OPENJSON(@DiscountPolicyIds) AS json_ids
        WHERE TRY_CAST(json_ids.[value] AS INT) IS NOT NULL
          AND EXISTS (SELECT 1 FROM discount_policy WHERE id = TRY_CAST(json_ids.[value] AS INT));
    END
    
    -- 8. Cập nhật trạng thái court_booking
    UPDATE court_booking
    SET [status] = N'Đã thanh toán'
    WHERE id = @CourtBookingId;
    
    -- 9. Trả về kết quả tính toán
    SELECT 
        1 AS Success,
        @InvoiceId AS InvoiceId,
        @CourtPrice AS CourtPrice, -- Tiền sân
        @ServicePrice AS ServicePrice, -- Tổng tiền dịch vụ
        @SubTotal AS SubTotal, -- Tổng tạm tính (Tiền sân + Dịch vụ)
        @FixedDiscountTotal AS FixedDiscountAmount, -- Tiền giảm cố định
        @PercentDiscountTotal AS PercentDiscountAmount, -- Tiền giảm theo %
        @FixedDiscountTotal + @PercentDiscountTotal AS TotalDiscountAmount, -- Tổng tiền giảm
        @FinalTotal AS FinalTotal, -- Tổng thanh toán
        @DiscountPolicyIds AS AppliedDiscountPolicyIds, -- Các mã khuyến mãi đã áp dụng
        N'Đã tạo hóa đơn thành công' AS Message;
END
GO
