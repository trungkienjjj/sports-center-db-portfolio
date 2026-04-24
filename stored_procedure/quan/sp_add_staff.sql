USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - MANAGER TẠO NHÂN VIÊN CHI NHÁNH
 * =================================================================================
 */

/*
 * Manager tạo nhân viên cho chi nhánh của mình (sp_add_staff)
 * 
 * Chức năng:
 *   - Manager tạo nhân viên mới cho chi nhánh mà mình quản lý
 *   - Tự động hash mật khẩu (SHA2_512 + Salt)
 *   - Mật khẩu mặc định "12345678" nếu không truyền
 *   - Giới hạn role: chỉ tạo Lễ tân, Kỹ thuật, Thu ngân (không tạo Manager/Admin)
 *   - Kiểm tra Manager có quyền với chi nhánh đó không
 *   - Trả về mật khẩu gốc để thông báo nhân viên mới
 *
 * Tham số đầu vào:
 *   @ManagerUserID    uniqueidentifier : ID tài khoản của Manager (để kiểm tra quyền)
 *   @Username         VARCHAR(255)      : Tên đăng nhập
 *   @PasswordPlain    VARCHAR(100) = NULL : Mật khẩu text (NULL → "12345678")
 *   @RoleID           INT               : Role (chỉ Lễ tân/Kỹ thuật/Thu ngân)
 *   @FullName         NVARCHAR(255)
 *   @Gender           NVARCHAR(10)      : Nam, Nữ, Khác
 *   @DOB              DATE
 *   @IDCardNumber     VARCHAR(20)
 *   @Address          NVARCHAR(500)
 *   @PhoneNumber      VARCHAR(20)
 *   @Email            VARCHAR(255)
 *   @BaseSalary       DECIMAL(10,2)
 *   @BaseAllowance    DECIMAL(10,2) = 0
 *   @BranchID         INT               : Chi nhánh (phải là chi nhánh của Manager)
 *
 * Kết quả trả về:
 *   Success, Message, AccountID, EmployeeID, Username, DefaultPassword, BranchName
 *
 * Ví dụ:
 *   EXEC sp_add_staff
 *       @ManagerUserID = 'GUID-CUA-MANAGER',
 *       @Username = 'letan.new',
 *       @RoleID = 3,  -- Lễ tân
 *       @FullName = N'Nguyễn Văn A',
 *       @Gender = N'Nam',
 *       @DOB = '1995-01-01',
 *       @IDCardNumber = '079195001234',
 *       @Address = N'123 Test',
 *       @PhoneNumber = '0909123456',
 *       @Email = 'a.nguyen@example.com',
 *       @BaseSalary = 8000000,
 *       @BaseAllowance = 500000,
 *       @BranchID = 1;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_add_staff
    @ManagerUserID    uniqueidentifier,
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
    @BaseAllowance    DECIMAL(10, 2) = 0,
    @BranchID         INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @NewAccountID     UNIQUEIDENTIFIER,
        @NewEmployeeID    INT,
        @FinalPassword    NVARCHAR(100),
        @PasswordHash     VARCHAR(500),
        @Salt             UNIQUEIDENTIFIER = NEWID(),
        @ManagerBranchID  INT,
        @ManagerRoleName  NVARCHAR(100),
        @TargetRoleName   NVARCHAR(100),
        @BranchName       NVARCHAR(255);

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra Manager tồn tại và lấy thông tin
         *-----------------------------------------------------*/
        IF @ManagerUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID Manager không được để trống.' AS Message, 
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, NULL AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        SELECT 
            @ManagerBranchID = e.branch_id,
            @ManagerRoleName = r.[name]
        FROM employee e
        JOIN account a ON e.user_id = a.id
        JOIN [role] r ON a.role_id = r.id
        WHERE a.id = @ManagerUserID;

        IF @ManagerBranchID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Manager không tồn tại hoặc không phải là nhân viên.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, NULL AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra Manager có quyền Quản lý không
         *-----------------------------------------------------*/
        IF @ManagerRoleName != N'Quản lý'
        BEGIN
            SELECT 0 AS Success, N'Chỉ Quản lý mới có quyền tạo nhân viên.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, NULL AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra BranchID khớp với chi nhánh của Manager
         *-----------------------------------------------------*/
        IF @BranchID IS NULL OR @BranchID != @ManagerBranchID
        BEGIN
            SELECT 0 AS Success, 
                   N'Manager chỉ có thể tạo nhân viên cho chi nhánh của mình (BranchID: ' 
                   + CAST(@ManagerBranchID AS NVARCHAR(10)) + N').' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, NULL AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Lấy tên chi nhánh
        SELECT @BranchName = [name] FROM branch WHERE id = @BranchID;

        /*------------------------------------------------------
         * 4. Kiểm tra Role hợp lệ (chỉ Lễ tân, Kỹ thuật, Thu ngân)
         *-----------------------------------------------------*/
        SELECT @TargetRoleName = [name] FROM [role] WHERE id = @RoleID;

        IF @TargetRoleName IS NULL
        BEGIN
            SELECT 0 AS Success, N'Role không tồn tại.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @TargetRoleName NOT IN (N'Lễ tân', N'Kỹ thuật', N'Thu ngân')
        BEGIN
            SELECT 0 AS Success, 
                   N'Manager chỉ được tạo nhân viên với vai trò: Lễ tân, Kỹ thuật, Thu ngân. Không được tạo: ' 
                   + @TargetRoleName AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 5. Xác định mật khẩu
         *-----------------------------------------------------*/
        IF @PasswordPlain IS NULL OR LTRIM(RTRIM(@PasswordPlain)) = ''
            SET @FinalPassword = N'12345678';
        ELSE
            SET @FinalPassword = LTRIM(RTRIM(@PasswordPlain));

        -- Hash mật khẩu
        SET @PasswordHash = CONVERT(VARCHAR(128), 
            HASHBYTES('SHA2_512', @FinalPassword + CAST(@Salt AS VARCHAR(36))), 2)
            + ':' + CAST(@Salt AS VARCHAR(36));

        /*------------------------------------------------------
         * 6. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @Username IS NULL OR LTRIM(RTRIM(@Username)) = ''
        BEGIN
            SELECT 0 AS Success, N'Tên đăng nhập không được để trống.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @FullName IS NULL OR @IDCardNumber IS NULL OR @PhoneNumber IS NULL OR @Email IS NULL OR @Address IS NULL
        BEGIN
            SELECT 0 AS Success, N'Thông tin cá nhân bắt buộc không được để trống.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra giới tính
        IF @Gender NOT IN (N'Nam', N'Nữ', N'Khác')
        BEGIN
            SELECT 0 AS Success, N'Giới tính phải là: Nam, Nữ hoặc Khác.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra lương không âm
        IF @BaseSalary < 0 OR @BaseAllowance < 0
        BEGIN
            SELECT 0 AS Success, N'Lương và phụ cấp phải là số không âm.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 7. Kiểm tra trùng lặp
         *-----------------------------------------------------*/
        IF EXISTS(SELECT 1 FROM account WHERE username = LTRIM(RTRIM(@Username)))
        BEGIN
            SELECT 0 AS Success, N'Tên đăng nhập đã tồn tại.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE id_card_number = @IDCardNumber)
        BEGIN
            SELECT 0 AS Success, N'Số CMND/CCCD đã được sử dụng.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE phone_number = @PhoneNumber)
        BEGIN
            SELECT 0 AS Success, N'Số điện thoại đã được sử dụng.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF EXISTS(SELECT 1 FROM employee WHERE email = @Email)
        BEGIN
            SELECT 0 AS Success, N'Email đã được sử dụng.' AS Message,
                   NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, NULL AS DefaultPassword, @BranchName AS BranchName;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 8. Tạo tài khoản
         *-----------------------------------------------------*/
        INSERT INTO account(username, [password], role_id, is_active)
        VALUES (LTRIM(RTRIM(@Username)), @PasswordHash, @RoleID, 1);

        SET @NewAccountID = (SELECT id FROM account WHERE username = LTRIM(RTRIM(@Username)));

        /*------------------------------------------------------
         * 9. Tạo nhân viên
         *-----------------------------------------------------*/
        INSERT INTO employee(
            full_name, gender, dob, id_card_number, [address], phone_number, email,
            [status], commission_rate, base_salary, base_allowance, user_id, branch_id
        )
        VALUES(
            @FullName, @Gender, @DOB, @IDCardNumber, @Address, @PhoneNumber, @Email,
            N'Đang làm', 0.00, @BaseSalary, @BaseAllowance, @NewAccountID, @BranchID
        );

        SET @NewEmployeeID = SCOPE_IDENTITY();

        /*------------------------------------------------------
         * 10. Thành công
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Manager đã tạo nhân viên "' + @FullName + N'" (' + @TargetRoleName 
            + N') cho chi nhánh "' + @BranchName + N'" thành công.' AS Message,
            @NewAccountID      AS AccountID,
            @NewEmployeeID     AS EmployeeID,
            LTRIM(RTRIM(@Username)) AS Username,
            @FinalPassword     AS DefaultPassword,
            @BranchName        AS BranchName;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi tạo nhân viên: ' + ERROR_MESSAGE() AS Message,
            NULL AS AccountID, NULL AS EmployeeID, NULL AS Username, 
            NULL AS DefaultPassword, NULL AS BranchName;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: sp_add_staff ===';
GO