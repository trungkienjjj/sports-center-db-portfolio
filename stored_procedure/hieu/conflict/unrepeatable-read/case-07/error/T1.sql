USE SportsCenterDB;
GO

-- =============================================
-- T2: QUẢN LÝ THAY ĐỔI CHÍNH SÁCH GIẢM GIÁ
-- Demo: Unrepeatable Read Error
-- Vai trò: Quản lý
-- Hành động: Thay đổi discount_policy và COMMIT (khác với Dirty Read là ROLLBACK)
-- =============================================

CREATE OR ALTER PROCEDURE SP_ChangeDiscountPolicy
    @DiscountPolicyId INT,
    @Name NVARCHAR(255) = NULL,
    @Type NVARCHAR(50) = NULL,
    @DiscountValue DECIMAL(10, 2) = NULL,
    @Description NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    IF NOT EXISTS (SELECT 1 FROM discount_policy WHERE id = @DiscountPolicyId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Chính sách giảm giá không tồn tại' AS Message;
        RETURN;
    END
    -- Lấy thông tin hiện tại
    
    DECLARE @CurrentName NVARCHAR(255);
    DECLARE @CurrentType NVARCHAR(50);
    DECLARE @CurrentDiscountValue DECIMAL(10, 2);
    DECLARE @CurrentDescription NVARCHAR(500);
    -- Sử dụng giá trị hiện tại nếu không truyền tham số mới
    SELECT 
        @CurrentName = [name],
        @CurrentType = [type],
        @CurrentDiscountValue = [discount_value],
        @CurrentDescription = [description]
    FROM discount_policy
    WHERE id = @DiscountPolicyId;
    
    SET @Name = ISNULL(@Name, @CurrentName);
    SET @Type = ISNULL(@Type, @CurrentType);
    SET @DiscountValue = ISNULL(@DiscountValue, @CurrentDiscountValue);
    SET @Description = ISNULL(@Description, @CurrentDescription);
    
    UPDATE discount_policy
    SET 
        [name] = @Name,
        [type] = @Type,
        [discount_value] = @DiscountValue,
        [description] = @Description
    WHERE id = @DiscountPolicyId;
    
    SELECT 
        1 AS Success,
        N'Đã cập nhật chính sách giảm giá thành công' AS Message,
        @DiscountPolicyId AS DiscountPolicyId,
        @Name AS NewName,
        @Type AS NewType,
        @Description AS NewDescription;
END
GO

SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

SELECT id, [name], [description], [type], [discount_value]
FROM discount_policy 
WHERE id = 1;


EXEC SP_ChangeDiscountPolicy
    @DiscountPolicyId = 1,
    @Description = N'Giảm 99% nhân ngày đẹp trời',
    @Type = N'Giảm theo phần trăm',
    @DiscountValue = 0.99;