USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - RESET MẬT KHẨU
 * =================================================================================
 */

/*
 * Cấp lại mật khẩu cho tài khoản (sp_reset_password)
 * 
 * Chức năng:
 *   - Admin/Manager reset mật khẩu cho nhân viên hoặc khách hàng
 *   - Tự động hash mật khẩu mới bằng SHA2_512 + Salt
 *   - Nếu không truyền mật khẩu mới → mặc định reset về "12345678"
 *   - Trả về mật khẩu gốc để thông báo cho người dùng
 *   - Kiểm tra tài khoản tồn tại và đang active
 *
 * Tham số đầu vào:
 *   @Username         VARCHAR(255)      : Tên đăng nhập cần reset (bắt buộc)
 *   @NewPasswordPlain VARCHAR(100) = NULL : Mật khẩu mới dạng text. Nếu NULL → dùng "12345678"
 *
 * Kết quả trả về:
 *   Success, Message, Username, NewPassword, Note
 *
 * Ví dụ:
 *   -- Reset về mật khẩu mặc định
 *   EXEC sp_reset_password @Username = 'letan.hong';
 *
 *   -- Reset về mật khẩu cụ thể
 *   EXEC sp_reset_password 
 *       @Username = 'letan.hong',
 *       @NewPasswordPlain = 'TempPass2025!';
 *
 * Lưu ý:
 *   - Yêu cầu người dùng đổi mật khẩu ngay lần đăng nhập đầu tiên
 *   - Chỉ Admin hoặc Manager mới có quyền thực hiện
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_reset_password
    @Username         VARCHAR(255),
    @NewPasswordPlain VARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @AccountID        UNIQUEIDENTIFIER,
        @IsActive         BIT,
        @FinalPassword    NVARCHAR(100),
        @PasswordHash     VARCHAR(500),
        @Salt             UNIQUEIDENTIFIER = NEWID(),
        @CurrentRoleName  NVARCHAR(100);

    BEGIN TRY
        /*------------------------------------------------------
         * 1. Kiểm tra tham số đầu vào
         *-----------------------------------------------------*/
        IF @Username IS NULL OR LTRIM(RTRIM(@Username)) = ''
        BEGIN
            SELECT 
                0 AS Success,
                N'Tên đăng nhập không được để trống.' AS Message,
                NULL AS Username,
                NULL AS NewPassword,
                NULL AS Note;
            RETURN;
        END

        SET @Username = LTRIM(RTRIM(@Username));

        /*------------------------------------------------------
         * 2. Kiểm tra tài khoản tồn tại
         *-----------------------------------------------------*/
        SELECT 
            @AccountID = a.id,
            @IsActive = a.is_active,
            @CurrentRoleName = r.[name]
        FROM account a
        JOIN [role] r ON a.role_id = r.id
        WHERE a.username = @Username;

        IF @AccountID IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Tài khoản không tồn tại.' AS Message,
                @Username AS Username,
                NULL AS NewPassword,
                NULL AS Note;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra trạng thái tài khoản
         *-----------------------------------------------------*/
        IF @IsActive = 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Tài khoản đã bị vô hiệu hóa. Vui lòng kích hoạt lại trước khi reset mật khẩu.' AS Message,
                @Username AS Username,
                NULL AS NewPassword,
                NULL AS Note;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Xác định mật khẩu mới
         *-----------------------------------------------------*/
        IF @NewPasswordPlain IS NULL OR LTRIM(RTRIM(@NewPasswordPlain)) = ''
            SET @FinalPassword = N'12345678';
        ELSE
            SET @FinalPassword = LTRIM(RTRIM(@NewPasswordPlain));

        /*------------------------------------------------------
         * 5. Hash mật khẩu mới với Salt
         *-----------------------------------------------------*/
        SET @PasswordHash = CONVERT(VARCHAR(128), 
            HASHBYTES('SHA2_512', @FinalPassword + CAST(@Salt AS VARCHAR(36))), 2)
            + ':' + CAST(@Salt AS VARCHAR(36));

        /*------------------------------------------------------
         * 6. Cập nhật mật khẩu
         *-----------------------------------------------------*/
        UPDATE account
        SET [password] = @PasswordHash
        WHERE id = @AccountID;

        /*------------------------------------------------------
         * 7. Trả về kết quả thành công
         *-----------------------------------------------------*/
        SELECT 
            1 AS Success,
            N'Reset mật khẩu thành công cho tài khoản: ' + @Username AS Message,
            @Username AS Username,
            @FinalPassword AS NewPassword,
            N'Lưu ý: Yêu cầu người dùng (' + @CurrentRoleName + N') đổi mật khẩu ngay khi đăng nhập lần đầu.' AS Note;

    END TRY
    BEGIN CATCH
        SELECT 
            0 AS Success,
            N'Lỗi khi reset mật khẩu: ' + ERROR_MESSAGE() AS Message,
            @Username AS Username,
            NULL AS NewPassword,
            NULL AS Note;
    END CATCH
END;
GO