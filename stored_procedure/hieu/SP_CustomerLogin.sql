USE SportsCenterDB;
GO

-- =============================================
-- 2. SP_CustomerLogin
-- Mô tả: Đăng nhập cho khách hàng
-- =============================================
CREATE OR ALTER PROCEDURE SP_CustomerLogin
    @Username VARCHAR(255),
    @Password VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @UserId UNIQUEIDENTIFIER;
    DECLARE @IsActive BIT;
    
    -- Kiểm tra tài khoản
    SELECT 
        @UserId = a.id,
        @IsActive = a.is_active
    FROM account a
    INNER JOIN [role] r ON a.role_id = r.id
    WHERE a.username = @Username 
        AND a.[password] = @Password
        AND r.[name] = N'Khách hàng/Member';
    
    -- Nếu không tìm thấy tài khoản
    IF @UserId IS NULL
    BEGIN
        SELECT 
            0 AS Success,
            N'Tên đăng nhập hoặc mật khẩu không đúng' AS Message;
        RETURN;
    END
    
    -- Nếu tài khoản bị khóa
    IF @IsActive = 0
    BEGIN
        SELECT 
            0 AS Success,
            N'Tài khoản đã bị khóa' AS Message;
        RETURN;
    END
    
    -- Đăng nhập thành công, trả về thông tin khách hàng
    SELECT 
        1 AS Success,
        N'Đăng nhập thành công' AS Message,
        c.id AS CustomerId,
        c.full_name AS FullName,
        c.email AS Email,
        c.phone_number AS PhoneNumber,
        c.bonus_point AS BonusPoint,
        cl.[name] AS CustomerLevel,
        cl.discount_rate AS DiscountRate
    FROM customer c
    INNER JOIN customer_level cl ON c.customer_level_id = cl.id
    WHERE c.user_id = @UserId;
END
GO
