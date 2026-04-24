USE SportsCenterDB;
GO
-- =============================================
-- SP_ChangeDiscountPolicy
-- Mô tả: Thay đổi thông tin chính sách giảm giá/khuyến mãi
-- Tham số:
--   @DiscountPolicyId - ID của chính sách cần thay đổi
--   @Name - Tên chính sách mới (optional)
--   @Type - Loại chính sách mới (optional)
--   @DiscountValue - Giá trị giảm giá mới (optional)
--   @Description - Mô tả mới (optional)
-- Lưu ý: 
--   - Chỉ truyền các tham số muốn thay đổi, giữ NULL cho các giá trị không đổi
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
    
    -- Cập nhật thông tin (KHÔNG có transaction ở đây, caller tự quản lý)
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
        @DiscountValue AS NewDiscountValue,
        @Description AS NewDescription;
END
GO

-- =============================================
-- SP_CreateDiscountPolicy
-- Mô tả: Tạo mới chính sách giảm giá/khuyến mãi
-- =============================================
CREATE OR ALTER PROCEDURE SP_CreateDiscountPolicy
    @Name NVARCHAR(255),
    @Type NVARCHAR(50),
    @DiscountValue DECIMAL(10, 2),
    @Description NVARCHAR(500) = NULL,
    @BranchId INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Kiểm tra chi nhánh tồn tại
        IF NOT EXISTS (SELECT 1 FROM branch WHERE id = @BranchId)
        BEGIN
            SELECT 
                0 AS Success,
                N'Chi nhánh không tồn tại' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Tạo chính sách giảm giá mới
        INSERT INTO discount_policy ([name], [type], [discount_value], [description], branch_id)
        VALUES (@Name, @Type, @DiscountValue, @Description, @BranchId);
        
        DECLARE @NewDiscountPolicyId INT = SCOPE_IDENTITY();
        
        COMMIT TRANSACTION;
        
        SELECT 
            1 AS Success,
            N'Đã tạo chính sách giảm giá thành công' AS Message,
            @NewDiscountPolicyId AS DiscountPolicyId;
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
-- SP_DeleteDiscountPolicy
-- Mô tả: Xóa chính sách giảm giá/khuyến mãi
-- =============================================
CREATE OR ALTER PROCEDURE SP_DeleteDiscountPolicy
    @DiscountPolicyId INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Kiểm tra chính sách tồn tại
        IF NOT EXISTS (SELECT 1 FROM discount_policy WHERE id = @DiscountPolicyId)
        BEGIN
            SELECT 
                0 AS Success,
                N'Chính sách giảm giá không tồn tại' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Kiểm tra xem chính sách có đang được sử dụng không
        IF EXISTS (SELECT 1 FROM invoice_discount WHERE discount_policy_id = @DiscountPolicyId)
        BEGIN
            SELECT 
                0 AS Success,
                N'Không thể xóa chính sách đang được sử dụng trong hóa đơn' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Xóa chính sách
        DELETE FROM discount_policy
        WHERE id = @DiscountPolicyId;
        
        COMMIT TRANSACTION;
        
        SELECT 
            1 AS Success,
            N'Đã xóa chính sách giảm giá thành công' AS Message;
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
-- SP_GetDiscountPoliciesByBranch
-- Mô tả: Xem danh sách chính sách giảm giá theo chi nhánh
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetDiscountPoliciesByBranch
    @BranchId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        dp.id AS DiscountPolicyId,
        dp.[name] AS PolicyName,
        dp.[type] AS PolicyType,
        dp.[discount_value] AS DiscountValue,
        dp.[description] AS Description,
        b.id AS BranchId,
        b.[name] AS BranchName,
        COUNT(DISTINCT id_inv.invoice_id) AS TimesUsed
    FROM discount_policy dp
    INNER JOIN branch b ON dp.branch_id = b.id
    LEFT JOIN invoice_discount id_inv ON dp.id = id_inv.discount_policy_id
    WHERE (@BranchId IS NULL OR dp.branch_id = @BranchId)
    GROUP BY dp.id, dp.[name], dp.[type], dp.[discount_value], dp.[description], b.id, b.[name]
    ORDER BY b.[name], dp.[name];
END
