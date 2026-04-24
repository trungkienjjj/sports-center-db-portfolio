USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - CẬP NHẬT THÔNG TIN NGƯỜI DÙNG
 * =================================================================================
 */

/*
 * Cập nhật thông tin tài khoản và hồ sơ người dùng (sp_update_user_info)
 * 
 * Chức năng:
 *   - Admin/Manager cập nhật thông tin nhân viên hoặc khách hàng
 *   - Hỗ trợ cập nhật một phần (chỉ cập nhật các trường được truyền vào)
 *   - Kiểm tra đầy đủ: tồn tại, trùng lặp, ràng buộc
 *   - Hỗ trợ cả Employee và Customer
 *
 * Tham số đầu vào:
 *   @UserID       uniqueidentifier : ID tài khoản cần cập nhật (bắt buộc)
 *   @NewRoleID    INT = NULL       : Vai trò mới (nếu muốn thay đổi)
 *   @FullName     NVARCHAR(255) = NULL
 *   @Gender       NVARCHAR(10) = NULL : Nam, Nữ, Khác
 *   @DOB          DATE = NULL
 *   @IDCardNumber VARCHAR(20) = NULL
 *   @Address      NVARCHAR(500) = NULL
 *   @PhoneNumber  VARCHAR(20) = NULL
 *   @Email        VARCHAR(255) = NULL
 *   @Status       NVARCHAR(50) = NULL : Chỉ cho Employee (Đang làm, Đã nghỉ việc, Nghỉ phép)
 *   @BaseSalary   DECIMAL(10,2) = NULL : Chỉ cho Employee
 *   @BaseAllowance DECIMAL(10,2) = NULL : Chỉ cho Employee
 *   @BranchID     INT = NULL : Chỉ cho Employee
 *
 * Kết quả trả về:
 *   Success, Message, UserID, UpdatedFields
 *
 * Ví dụ:
 *   -- Cập nhật email và số điện thoại
 *   EXEC sp_update_user_info
 *       @UserID = 'GUID-HERE',
 *       @Email = 'newemail@example.com',
 *       @PhoneNumber = '0909123456';
 *
 *   -- Chuyển chi nhánh và tăng lương
 *   EXEC sp_update_user_info
 *       @UserID = 'GUID-HERE',
 *       @BranchID = 2,
 *       @BaseSalary = 10000000;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_update_user_info
    @UserID        uniqueidentifier,
    @NewRoleID     INT = NULL,
    @FullName      NVARCHAR(255) = NULL,
    @Gender        NVARCHAR(10) = NULL,
    @DOB           DATE = NULL,
    @IDCardNumber  VARCHAR(20) = NULL,
    @Address       NVARCHAR(500) = NULL,
    @PhoneNumber   VARCHAR(20) = NULL,
    @Email         VARCHAR(255) = NULL,
    @Status        NVARCHAR(50) = NULL,
    @BaseSalary    DECIMAL(10, 2) = NULL,
    @BaseAllowance DECIMAL(10, 2) = NULL,
    @BranchID      INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @AccountExists    BIT = 0,
        @IsEmployee       BIT = 0,
        @IsCustomer       BIT = 0,
        @EmployeeID       INT,
        @CustomerID       INT,
        @CurrentRoleName  NVARCHAR(100),
        @UpdatedFields    NVARCHAR(MAX) = N'',
        @UpdateCount      INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tài khoản tồn tại và xác định loại
         *-----------------------------------------------------*/
        IF @UserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'UserID không được để trống.' AS Message, NULL AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra tài khoản
        IF NOT EXISTS(SELECT 1 FROM account WHERE id = @UserID)
        BEGIN
            SELECT 0 AS Success, N'Tài khoản không tồn tại.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Xác định là Employee hay Customer
        SELECT @EmployeeID = id FROM employee WHERE user_id = @UserID;
        SELECT @CustomerID = id FROM customer WHERE user_id = @UserID;

        IF @EmployeeID IS NOT NULL SET @IsEmployee = 1;
        IF @CustomerID IS NOT NULL SET @IsCustomer = 1;

        -- Lấy thông tin role hiện tại
        SELECT @CurrentRoleName = r.[name]
        FROM account a
        JOIN [role] r ON a.role_id = r.id
        WHERE a.id = @UserID;

        /*------------------------------------------------------
         * 2. Kiểm tra quyền cập nhật Role
         *-----------------------------------------------------*/
        IF @NewRoleID IS NOT NULL
        BEGIN
            -- Không cho đổi Role của Admin hệ thống
            IF @CurrentRoleName = N'Quản trị hệ thống'
            BEGIN
                SELECT 0 AS Success, N'Không thể thay đổi vai trò của Quản trị hệ thống.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END

            -- Kiểm tra Role mới tồn tại
            IF NOT EXISTS(SELECT 1 FROM [role] WHERE id = @NewRoleID)
            BEGIN
                SELECT 0 AS Success, N'Vai trò mới không tồn tại.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
        END

        /*------------------------------------------------------
         * 3. Kiểm tra các ràng buộc
         *-----------------------------------------------------*/
        -- Kiểm tra giới tính
        IF @Gender IS NOT NULL AND @Gender NOT IN (N'Nam', N'Nữ', N'Khác')
        BEGIN
            SELECT 0 AS Success, N'Giới tính phải là: Nam, Nữ hoặc Khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra trạng thái nhân viên
        IF @Status IS NOT NULL AND @Status NOT IN (N'Đang làm', N'Đã nghỉ việc', N'Nghỉ phép')
        BEGIN
            SELECT 0 AS Success, N'Trạng thái phải là: Đang làm, Đã nghỉ việc, hoặc Nghỉ phép.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra lương không âm
        IF (@BaseSalary IS NOT NULL AND @BaseSalary < 0) OR (@BaseAllowance IS NOT NULL AND @BaseAllowance < 0)
        BEGIN
            SELECT 0 AS Success, N'Lương và phụ cấp phải là số không âm.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra Branch tồn tại
        IF @BranchID IS NOT NULL AND NOT EXISTS(SELECT 1 FROM branch WHERE id = @BranchID)
        BEGIN
            SELECT 0 AS Success, N'Chi nhánh không tồn tại.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Kiểm tra trùng lặp
         *-----------------------------------------------------*/
        -- Kiểm tra CMND/CCCD
        IF @IDCardNumber IS NOT NULL
        BEGIN
            IF @IsEmployee = 1 AND EXISTS(SELECT 1 FROM employee WHERE id_card_number = @IDCardNumber AND id != @EmployeeID)
            BEGIN
                SELECT 0 AS Success, N'Số CMND/CCCD đã được sử dụng bởi nhân viên khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
            
            IF @IsCustomer = 1 AND EXISTS(SELECT 1 FROM customer WHERE id_card_number = @IDCardNumber AND id != @CustomerID)
            BEGIN
                SELECT 0 AS Success, N'Số CMND/CCCD đã được sử dụng bởi khách hàng khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
        END

        -- Kiểm tra số điện thoại
        IF @PhoneNumber IS NOT NULL
        BEGIN
            IF @IsEmployee = 1 AND EXISTS(SELECT 1 FROM employee WHERE phone_number = @PhoneNumber AND id != @EmployeeID)
            BEGIN
                SELECT 0 AS Success, N'Số điện thoại đã được sử dụng bởi nhân viên khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
            
            IF @IsCustomer = 1 AND EXISTS(SELECT 1 FROM customer WHERE phone_number = @PhoneNumber AND id != @CustomerID)
            BEGIN
                SELECT 0 AS Success, N'Số điện thoại đã được sử dụng bởi khách hàng khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
        END

        -- Kiểm tra email
        IF @Email IS NOT NULL
        BEGIN
            IF @IsEmployee = 1 AND EXISTS(SELECT 1 FROM employee WHERE email = @Email AND id != @EmployeeID)
            BEGIN
                SELECT 0 AS Success, N'Email đã được sử dụng bởi nhân viên khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
            
            IF @IsCustomer = 1 AND EXISTS(SELECT 1 FROM customer WHERE email = @Email AND id != @CustomerID)
            BEGIN
                SELECT 0 AS Success, N'Email đã được sử dụng bởi khách hàng khác.' AS Message, @UserID AS UserID, NULL AS UpdatedFields;
                ROLLBACK TRANSACTION;
                RETURN;
            END
        END

        /*------------------------------------------------------
         * 5. Cập nhật Role (nếu có)
         *-----------------------------------------------------*/
        IF @NewRoleID IS NOT NULL
        BEGIN
            UPDATE account
            SET role_id = @NewRoleID
            WHERE id = @UserID;

            SET @UpdatedFields = @UpdatedFields + N'Role, ';
            SET @UpdateCount = @UpdateCount + 1;
        END

        /*------------------------------------------------------
         * 6. Cập nhật Employee (nếu là nhân viên)
         *-----------------------------------------------------*/
        IF @IsEmployee = 1
        BEGIN
            UPDATE employee
            SET
                full_name = CASE WHEN @FullName IS NOT NULL THEN @FullName ELSE full_name END,
                gender = CASE WHEN @Gender IS NOT NULL THEN @Gender ELSE gender END,
                dob = CASE WHEN @DOB IS NOT NULL THEN @DOB ELSE dob END,
                id_card_number = CASE WHEN @IDCardNumber IS NOT NULL THEN @IDCardNumber ELSE id_card_number END,
                [address] = CASE WHEN @Address IS NOT NULL THEN @Address ELSE [address] END,
                phone_number = CASE WHEN @PhoneNumber IS NOT NULL THEN @PhoneNumber ELSE phone_number END,
                email = CASE WHEN @Email IS NOT NULL THEN @Email ELSE email END,
                [status] = CASE WHEN @Status IS NOT NULL THEN @Status ELSE [status] END,
                base_salary = CASE WHEN @BaseSalary IS NOT NULL THEN @BaseSalary ELSE base_salary END,
                base_allowance = CASE WHEN @BaseAllowance IS NOT NULL THEN @BaseAllowance ELSE base_allowance END,
                branch_id = CASE WHEN @BranchID IS NOT NULL THEN @BranchID ELSE branch_id END
            WHERE id = @EmployeeID;

            -- Ghi nhận các trường đã cập nhật
            IF @FullName IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'FullName, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Gender IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Gender, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @DOB IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'DOB, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @IDCardNumber IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'IDCardNumber, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Address IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Address, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @PhoneNumber IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'PhoneNumber, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Email IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Email, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Status IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Status, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @BaseSalary IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'BaseSalary, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @BaseAllowance IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'BaseAllowance, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @BranchID IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Branch, '; SET @UpdateCount = @UpdateCount + 1; END
        END

        /*------------------------------------------------------
         * 7. Cập nhật Customer (nếu là khách hàng)
         *-----------------------------------------------------*/
        IF @IsCustomer = 1
        BEGIN
            UPDATE customer
            SET
                full_name = CASE WHEN @FullName IS NOT NULL THEN @FullName ELSE full_name END,
                gender = CASE WHEN @Gender IS NOT NULL THEN @Gender ELSE gender END,
                dob = CASE WHEN @DOB IS NOT NULL THEN @DOB ELSE dob END,
                id_card_number = CASE WHEN @IDCardNumber IS NOT NULL THEN @IDCardNumber ELSE id_card_number END,
                [address] = CASE WHEN @Address IS NOT NULL THEN @Address ELSE [address] END,
                phone_number = CASE WHEN @PhoneNumber IS NOT NULL THEN @PhoneNumber ELSE phone_number END,
                email = CASE WHEN @Email IS NOT NULL THEN @Email ELSE email END
            WHERE id = @CustomerID;

            -- Ghi nhận các trường đã cập nhật
            IF @FullName IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'FullName, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Gender IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Gender, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @DOB IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'DOB, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @IDCardNumber IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'IDCardNumber, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Address IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Address, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @PhoneNumber IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'PhoneNumber, '; SET @UpdateCount = @UpdateCount + 1; END
            IF @Email IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Email, '; SET @UpdateCount = @UpdateCount + 1; END
        END

        /*------------------------------------------------------
         * 8. Kiểm tra có cập nhật gì không
         *-----------------------------------------------------*/
        IF @UpdateCount = 0
        BEGIN
            SELECT 
                0 AS Success, 
                N'Không có trường nào được cập nhật. Vui lòng truyền ít nhất một giá trị mới.' AS Message,
                @UserID AS UserID,
                NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 9. Hoàn tất
         *-----------------------------------------------------*/
        -- Bỏ dấu phẩy cuối
        IF LEN(@UpdatedFields) > 0
            SET @UpdatedFields = LEFT(@UpdatedFields, LEN(@UpdatedFields) - 2);

        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Cập nhật thông tin thành công. Số trường đã cập nhật: ' + CAST(@UpdateCount AS NVARCHAR(10)) AS Message,
            @UserID AS UserID,
            @UpdatedFields AS UpdatedFields;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi cập nhật thông tin: ' + ERROR_MESSAGE() AS Message,
            @UserID AS UserID,
            NULL AS UpdatedFields;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: sp_update_user_info ===';
GO