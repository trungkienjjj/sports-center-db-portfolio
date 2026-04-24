USE SportsCenterDB;
GO

-- =============================================
-- T1: QUẢN LÝ THAY ĐỔI CHÍNH SÁCH GIẢM GIÁ
-- Demo: Dirty Read Error
-- Vai trò: Quản lý
-- Hành động: Thay đổi description của discount_policy, delay 10s, rồi ROLLBACK
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
    BEGIN TRAN;
    -- Kiểm tra chính sách tồn tại
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
    
    SELECT 
        @CurrentName = [name],
        @CurrentType = [type],
        @CurrentDiscountValue = [discount_value],
        @CurrentDescription = [description]
    FROM discount_policy
    WHERE id = @DiscountPolicyId;
    
    -- Sử dụng giá trị hiện tại nếu không truyền tham số mới
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
    
    -- Trả về kết quả thành công
    SELECT 
        1 AS Success,
        N'Đã cập nhật chính sách giảm giá thành công' AS Message,
        @DiscountPolicyId AS DiscountPolicyId,
        @Name AS NewName,
        @Type AS NewType,
        @Description AS NewDescription;
    WAITFOR DELAY '00:00:10';
    ROLLBACK TRAN;
END
GO

-- demo lỗi dirty read từ T1
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
GO

SELECT id, [name], [description] , [type], [discount_value]
FROM discount_policy 
WHERE id = 1;

EXEC SP_ChangeDiscountPolicy
    @DiscountPolicyId = 1,
    @Description = N'Giảm 1% nhân ngày đẹp trời',
    @Type = N'Giảm theo phần trăm',
    @DiscountValue = 0.01;