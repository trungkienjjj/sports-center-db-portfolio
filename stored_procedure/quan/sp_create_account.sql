USE SportsCenterDB;
GO
/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: QUẢN LÝ NHÂN SỰ
 * =================================================================================
 */

/*
 * Tạo tài khoản nhân viên mới (sp_create_account)
 * Chức năng:
 *   - Tạo tài khoản đăng nhập + tự động hash mật khẩu
 *   - Tạo hồ sơ nhân viên và liên kết
 *   - Nếu không truyền mật khẩu → tự động dùng "12345678"
 *   - Trả về mật khẩu gốc để in phiếu đưa nhân viên
 *
 * Tham số đầu vào:
 *   @Username         VARCHAR(255)      : Tên đăng nhập (bắt buộc, duy nhất)
 *   @PasswordPlain    VARCHAR(100) = NULL : Mật khẩu dạng text. Nếu NULL → dùng mặc định 12345678
 *   @RoleID           INT               : Mã vai trò
 *   @FullName         NVARCHAR(255)     : Họ tên
 *   @Gender           NVARCHAR(10)      : Giới tính (N'Nam', N'Nữ', N'Khác')
 *   @DOB              DATE              : Ngày sinh
 *   @IDCardNumber     VARCHAR(20)       : CMND/CCCD (duy nhất)
 *   @Address          NVARCHAR(500)     : Địa chỉ
 *   @PhoneNumber      VARCHAR(20)       : SĐT (duy nhất)
 *   @Email            VARCHAR(255)      : Email (duy nhất)
 *   @BaseSalary       DECIMAL(10,2)     : Lương cơ bản
 *   @BaseAllowance    DECIMAL(10,2) = 0 : Phụ cấp cơ bản (mặc định 0)
 *   @BranchID         INT               : Chi nhánh
 *
 * Kết quả trả về:
 *   Success, Message, AccountID, EmployeeID, Username, DefaultPassword
 *
 * Ví dụ:
 *   EXEC sp_create_account
 *       @Username = 'letan.hong', 
 *       @FullName = N'Trần Hồng',
 *       @Gender = N'Nữ',
 *       @DOB = '1995-03-15',
 *       @IDCardNumber = '079095001234',
 *       @Address = N'123 Nguyễn Huệ, Q1, HCM',
 *       @PhoneNumber = '0909123456',
 *       @Email = 'hong.tran@vietsport.com',
 *       @BaseSalary = 8000000,
 *       @BaseAllowance = 500000,
 *       @RoleID = 3,
 *       @BranchID = 1;
 *
 *   → Mật khẩu tự động = 12345678
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_create_account
    @Username         VARCHAR(255),
    @PasswordPlain    VARCHAR(100) = NULL,
    @RoleID           INT,
    @FullName         NVARCHAR(255),
    @Gender           NVARCHAR(10),
    @DOB              DATE,
    @IDCardNumber     VARCHAR(20),
    @Address          NVARCHAR(500),
    @PhoneNumber      VARCHAR(20),
    @Email            VARCHAR(255),
    @BaseSalary       DECIMAL(10, 2),
    @BaseAllowance    DECIMAL(10, 2) = 0,  -- THÊM THAM SỐ NÀY
    @BranchID         INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @NewAccountID     UNIQUEIDENTIFIER,
        @NewEmployeeID    INT,
        @FinalPassword    NVARCHAR(100),
        @PasswordHash     VARCHAR(500),
        @Salt             UNIQUEIDENTIFIER = NEWID();

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Xác định mật khẩu (mặc định hoặc do người gọi)
         *-----------------------------------------------------*/
        IF @PasswordPlain IS NULL OR LTRIM(RTRIM(@PasswordPlain)) = ''
            SET @FinalPassword = N'12345678';
        ELSE
            SET @FinalPassword = LTRIM(RTRIM(@PasswordPlain));

        -- Hash mật khẩu: SHA2_512 + Salt
        SET @PasswordHash = CONVERT(VARCHAR(128), 
            HASHBYTES('SHA2_512', @FinalPassword + CAST(@Salt AS VARCHAR(36))), 2)
            + ':' + CAST(@Salt AS VARCHAR(36));

        /*------------------------------------------------------
         * 2. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @Username IS NULL OR LTRIM(RTRIM(@Username)) = ''
        BEGIN
            SELECT 0 AS Success, N'Tên đăng nhập không được để trống.' AS Message;
            ROLLBACK; RETURN;
        END

        IF @RoleID IS NULL OR NOT EXISTS(SELECT 1 FROM [role] WHERE id = @RoleID)
        BEGIN
            SELECT 0 AS Success, N'Mã vai trò không tồn tại.' AS Message;
            ROLLBACK; RETURN;
        END

        IF @BranchID IS NULL OR NOT EXISTS(SELECT 1 FROM branch WHERE id = @BranchID)
        BEGIN
            SELECT 0 AS Success, N'Chi nhánh không tồn tại.' AS Message;
            ROLLBACK; RETURN;
        END

        IF @FullName IS NULL OR @IDCardNumber IS NULL OR @PhoneNumber IS NULL OR @Email IS NULL
        BEGIN
            SELECT 0 AS Success, N'Thông tin cá nhân bắt buộc không được để trống.' AS Message;
            ROLLBACK; RETURN;
        END

        IF @Address IS NULL OR LTRIM(RTRIM(@Address)) = ''
        BEGIN
            SELECT 0 AS Success, N'Địa chỉ không được để trống.' AS Message;
            ROLLBACK; RETURN;
        END

        -- KIỂM TRA GIỚI TÍNH HỢP LỆ (theo constraint CK_R1102_employee_gender)
        IF @Gender NOT IN (N'Nam', N'Nữ', N'Khác')
        BEGIN
            SELECT 0 AS Success, N'Giới tính phải là: Nam, Nữ hoặc Khác.' AS Message;
            ROLLBACK; RETURN;
        END

        -- KIỂM TRA LƯƠNG VÀ PHỤ CẤP KHÔNG ÂM (theo constraint CK_R1103)
        IF @BaseSalary < 0 OR @BaseAllowance < 0
        BEGIN
            SELECT 0 AS Success, N'Lương và phụ cấp phải là số không âm.' AS Message;
            ROLLBACK; RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra trùng lặp
         *-----------------------------------------------------*/
        IF EXISTS(SELECT 1 FROM account WHERE username = LTRIM(RTRIM(@Username)))
        BEGIN
            SELECT 0 AS Success, N'Tên đăng nhập đã tồn tại.' AS Message;
            ROLLBACK; RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE id_card_number = @IDCardNumber)
        BEGIN
            SELECT 0 AS Success, N'Số CMND/CCCD đã được sử dụng.' AS Message;
            ROLLBACK; RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE phone_number = @PhoneNumber)
        BEGIN
            SELECT 0 AS Success, N'Số điện thoại đã được sử dụng.' AS Message;
            ROLLBACK; RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE email = @Email)
        BEGIN
            SELECT 0 AS Success, N'Email đã được sử dụng.' AS Message;
            ROLLBACK; RETURN;
        END

        /*------------------------------------------------------
         * 4. Tạo tài khoản
         *-----------------------------------------------------*/
        INSERT INTO account(username, [password], role_id, is_active)
        VALUES (LTRIM(RTRIM(@Username)), @PasswordHash, @RoleID, 1);

        SET @NewAccountID = (SELECT id FROM account WHERE username = LTRIM(RTRIM(@Username)));

        /*------------------------------------------------------
         * 5. Tạo nhân viên - FIXED: Đúng thứ tự cột và giá trị
         *-----------------------------------------------------*/
        INSERT INTO employee(
            full_name, 
            gender, 
            dob, 
            id_card_number, 
            [address], 
            phone_number, 
            email,
            [status],              -- SỬA: Dùng giá trị đúng theo constraint
            commission_rate,       -- Đặt trước base_salary
            base_salary, 
            base_allowance,        -- THÊM CỘT NÀY
            user_id,               -- Đổi thứ tự
            branch_id
        )
        VALUES(
            @FullName, 
            @Gender, 
            @DOB, 
            @IDCardNumber, 
            @Address, 
            @PhoneNumber, 
            @Email,
            N'Đang làm',           -- SỬA: Phải là N'Đang làm' (theo CK_R1101_employee_status)
            0.00,                  -- commission_rate mặc định
            @BaseSalary,
            @BaseAllowance,        -- THÊM GIÁ TRỊ NÀY
            @NewAccountID,
            @BranchID
        );

        SET @NewEmployeeID = SCOPE_IDENTITY();

        /*------------------------------------------------------
         * 6. Thành công
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Tạo tài khoản nhân viên thành công.' AS Message,
            @NewAccountID      AS AccountID,
            @NewEmployeeID     AS EmployeeID,
            LTRIM(RTRIM(@Username)) AS Username,
            @FinalPassword     AS DefaultPassword,
            N'Lưu ý: Yêu cầu nhân viên đổi mật khẩu khi đăng nhập lần đầu.' AS Note;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi tạo tài khoản: ' + ERROR_MESSAGE() AS Message,
            NULL AS AccountID, 
            NULL AS EmployeeID, 
            NULL AS Username, 
            NULL AS DefaultPassword, 
            NULL AS Note;
    END CATCH
END;
GO