USE SportsCenterDB;
GO


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
        WHERE DiscountType = N'co_dinh';
        
        -- Trừ tiền giảm cố định khỏi SubTotal
        DECLARE @AfterFixedDiscount DECIMAL(10, 2) = @SubTotal - @FixedDiscountTotal;
        IF @AfterFixedDiscount < 0 SET @AfterFixedDiscount = 0;
        
        -- Bước 2: Áp dụng GIẢM THEO % trên số tiền đã giảm cố định
        DECLARE @TotalPercentRate DECIMAL(10, 4) = 0;
        
        SELECT @TotalPercentRate = ISNULL(SUM(DiscountValue), 0)
        FROM @DiscountTable
        WHERE DiscountType = N'phan_tram';
        
        -- Tính tiền giảm theo %
        SET @PercentDiscountTotal = @AfterFixedDiscount * @TotalPercentRate;
    END
    
    -- 5. Tính TỔNG THANH TOÁN (Tổng tạm tính - Giảm cố định - Giảm %)
    SET @FinalTotal = @SubTotal - @FixedDiscountTotal - @PercentDiscountTotal;
    IF @FinalTotal < 0 SET @FinalTotal = 0;
    
    -- TẠO HÓA ĐƠN trong bảng invoice
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
    
    -- Lưu discount policies vào bảng invoice_discount
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
    
    --Cập nhật trạng thái court_booking
    UPDATE court_booking
    SET [status] = N'Đã thanh toán'
    WHERE id = @CourtBookingId;
    
    --Trả về kết quả tính toán
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