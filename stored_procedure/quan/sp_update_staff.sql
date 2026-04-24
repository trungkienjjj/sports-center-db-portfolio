USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - MANAGER CẬP NHẬT HỒ SƠ NHÂN VIÊN
 * 
 * Chức năng:
 *   - Manager cập nhật thông tin nhân viên trong chi nhánh của mình
 *   - Hỗ trợ cập nhật một phần (chỉ cập nhật trường được truyền vào)
 *   - Kiểm tra quyền: chỉ cập nhật nhân viên cùng chi nhánh
 *   - Không cho phép cập nhật Manager khác
 *   - Kiểm tra trùng lặp email, phone
 *   - Ghi nhận các trường đã thay đổi
 *
 * Tham số đầu vào:
 *   @ManagerUserID  uniqueidentifier : ID tài khoản Manager (kiểm tra quyền)
 *   @EmployeeID     INT              : ID nhân viên cần cập nhật
 *   @FullName       NVARCHAR(255) = NULL
 *   @Address        NVARCHAR(500) = NULL
 *   @PhoneNumber    VARCHAR(20) = NULL
 *   @Email          VARCHAR(255) = NULL
 *   @Status         NVARCHAR(50) = NULL : Đang làm, Đã nghỉ việc, Nghỉ phép
 *   @BaseSalary     DECIMAL(10,2) = NULL
 *   @BaseAllowance  DECIMAL(10,2) = NULL
 *
 * Kết quả trả về:
 *   Success, Message, EmployeeID, EmployeeName, UpdatedFields
 *
 * Ví dụ:
 *   EXEC sp_update_staff
 *       @ManagerUserID = 'GUID-MANAGER',
 *       @EmployeeID = 5,
 *       @PhoneNumber = '0909123456',
 *       @BaseSalary = 10000000;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_update_staff
    @ManagerUserID  uniqueidentifier,
    @EmployeeID     INT,
    @FullName       NVARCHAR(255) = NULL,
    @Address        NVARCHAR(500) = NULL,
    @PhoneNumber    VARCHAR(20) = NULL,
    @Email          VARCHAR(255) = NULL,
    @Status         NVARCHAR(50) = NULL,
    @BaseSalary     DECIMAL(10, 2) = NULL,
    @BaseAllowance  DECIMAL(10, 2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ManagerBranchID    INT,
        @ManagerRoleName    NVARCHAR(100),
        @EmployeeBranchID   INT,
        @EmployeeName       NVARCHAR(255),
        @EmployeeRoleName   NVARCHAR(100),
        @BranchName         NVARCHAR(255),
        @UpdatedFields      NVARCHAR(MAX) = N'',
        @UpdateCount        INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @ManagerUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID Manager không được để trống.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @EmployeeID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID nhân viên không được để trống.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra Manager tồn tại
         *-----------------------------------------------------*/
        SELECT 
            @ManagerBranchID = e.branch_id,
            @ManagerRoleName = r.[name]
        FROM employee e
        JOIN account a ON e.user_id = a.id
        JOIN [role] r ON a.role_id = r.id
        WHERE a.id = @ManagerUserID;

        IF @ManagerBranchID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Manager không tồn tại.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @ManagerRoleName != N'Quản lý'
        BEGIN
            SELECT 0 AS Success, N'Chỉ Quản lý mới có quyền cập nhật hồ sơ nhân viên.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra nhân viên tồn tại
         *-----------------------------------------------------*/
        SELECT 
            @EmployeeBranchID = e.branch_id,
            @EmployeeName = e.full_name,
            @EmployeeRoleName = r.[name],
            @BranchName = b.[name]
        FROM employee e
        JOIN account a ON e.user_id = a.id
        JOIN [role] r ON a.role_id = r.id
        JOIN branch b ON e.branch_id = b.id
        WHERE e.id = @EmployeeID;

        IF @EmployeeName IS NULL
        BEGIN
            SELECT 0 AS Success, N'Nhân viên không tồn tại.' AS Message,
                   @EmployeeID AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Kiểm tra quyền: cùng chi nhánh
         *-----------------------------------------------------*/
        IF @EmployeeBranchID != @ManagerBranchID
        BEGIN
            SELECT 0 AS Success, N'Manager chỉ cập nhật nhân viên trong chi nhánh của mình.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 5. Không cho phép cập nhật Manager khác
         *-----------------------------------------------------*/
        IF @EmployeeRoleName = N'Quản lý'
        BEGIN
            SELECT 0 AS Success, N'Không thể cập nhật hồ sơ Manager khác.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 6. Kiểm tra có cập nhật gì không
         *-----------------------------------------------------*/
        IF @FullName IS NULL AND @Address IS NULL AND @PhoneNumber IS NULL 
           AND @Email IS NULL AND @Status IS NULL AND @BaseSalary IS NULL AND @BaseAllowance IS NULL
        BEGIN
            SELECT 0 AS Success, N'Không có trường nào được cập nhật.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 7. Validation
         *-----------------------------------------------------*/
        -- Kiểm tra status
        IF @Status IS NOT NULL AND @Status NOT IN (N'Đang làm', N'Đã nghỉ việc', N'Nghỉ phép')
        BEGIN
            SELECT 0 AS Success, N'Trạng thái phải là: Đang làm, Đã nghỉ việc, hoặc Nghỉ phép.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra lương không âm
        IF (@BaseSalary IS NOT NULL AND @BaseSalary < 0) OR (@BaseAllowance IS NOT NULL AND @BaseAllowance < 0)
        BEGIN
            SELECT 0 AS Success, N'Lương và phụ cấp phải là số không âm.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra trùng phone
        IF @PhoneNumber IS NOT NULL AND EXISTS(
            SELECT 1 FROM employee WHERE phone_number = @PhoneNumber AND id != @EmployeeID
        )
        BEGIN
            SELECT 0 AS Success, N'Số điện thoại đã được sử dụng bởi nhân viên khác.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra trùng email
        IF @Email IS NOT NULL AND EXISTS(
            SELECT 1 FROM employee WHERE email = @Email AND id != @EmployeeID
        )
        BEGIN
            SELECT 0 AS Success, N'Email đã được sử dụng bởi nhân viên khác.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, NULL AS UpdatedFields;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 8. Cập nhật dữ liệu
         *-----------------------------------------------------*/
        UPDATE employee
        SET
            full_name = CASE WHEN @FullName IS NOT NULL THEN @FullName ELSE full_name END,
            [address] = CASE WHEN @Address IS NOT NULL THEN @Address ELSE [address] END,
            phone_number = CASE WHEN @PhoneNumber IS NOT NULL THEN @PhoneNumber ELSE phone_number END,
            email = CASE WHEN @Email IS NOT NULL THEN @Email ELSE email END,
            [status] = CASE WHEN @Status IS NOT NULL THEN @Status ELSE [status] END,
            base_salary = CASE WHEN @BaseSalary IS NOT NULL THEN @BaseSalary ELSE base_salary END,
            base_allowance = CASE WHEN @BaseAllowance IS NOT NULL THEN @BaseAllowance ELSE base_allowance END
        WHERE id = @EmployeeID;

        /*------------------------------------------------------
         * 9. Ghi nhận các trường đã cập nhật
         *-----------------------------------------------------*/
        IF @FullName IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'FullName, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @Address IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Address, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @PhoneNumber IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'PhoneNumber, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @Email IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Email, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @Status IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'Status, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @BaseSalary IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'BaseSalary, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @BaseAllowance IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'BaseAllowance, '; SET @UpdateCount = @UpdateCount + 1; END

        -- Bỏ dấu phẩy cuối
        IF LEN(@UpdatedFields) > 0
            SET @UpdatedFields = LEFT(@UpdatedFields, LEN(@UpdatedFields) - 2);

        /*------------------------------------------------------
         * 10. Commit và trả về kết quả
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Cập nhật hồ sơ nhân viên "' + @EmployeeName + N'" (' + @EmployeeRoleName 
            + N') tại "' + @BranchName + N'" thành công. Số trường cập nhật: ' 
            + CAST(@UpdateCount AS NVARCHAR(10)) AS Message,
            @EmployeeID AS EmployeeID,
            @EmployeeName AS EmployeeName,
            @UpdatedFields AS UpdatedFields;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi cập nhật hồ sơ: ' + ERROR_MESSAGE() AS Message,
            @EmployeeID AS EmployeeID, NULL AS EmployeeName, NULL AS UpdatedFields;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: sp_update_staff ===';
GO