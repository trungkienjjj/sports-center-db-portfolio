USE SportsCenterDB;
GO

-- =============================================
-- 3. SP_ResetPassword
-- Mô tả: Quên mật khẩu - Reset password bằng email hoặc phone
-- =============================================
CREATE OR ALTER PROCEDURE SP_ResetPassword
    @Email VARCHAR(255),
    @NewPassword VARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @UserId UNIQUEIDENTIFIER;
    
    -- Tìm tài khoản qua email hoặc phone
    SELECT @UserId = c.user_id
    FROM customer c
    WHERE c.email = @Email
    
    IF @UserId IS NULL
    BEGIN
        SELECT 
            0 AS Success,
            N'Không tìm thấy tài khoản với email/số điện thoại này' AS Message;
        RETURN;
    END
    
    -- Cập nhật mật khẩu mới
    UPDATE account
    SET [password] = @NewPassword
    WHERE id = @UserId;
    
    SELECT 
        1 AS Success,
        N'Mật khẩu đã được đặt lại thành công' AS Message;
END
GO
