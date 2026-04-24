USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - MANAGER VÔ HIỆU HÓA NHÂN VIÊN (KHÔNG XÓA)
 * Người thực hiện: [Tên bạn]
 * Ngày cập nhật: 07/12/2025
 * =================================================================================
 */

/*
 * Manager vô hiệu hóa nhân viên trong chi nhánh (USP_MANAGER_DEACTIVATE_EMPLOYEE)
 * 
 * Chức năng:
 *   - Manager đánh dấu nhân viên "Đã nghỉ việc" thay vì xóa
 *   - Khóa tài khoản (is_active = 0)
 *   - Chỉ được vô hiệu hóa nhân viên trong chi nhánh của mình
 *   - KHÔNG được vô hiệu hóa Manager khác hoặc chính mình
 *   - Giữ toàn bộ dữ liệu lịch sử (không xóa)
 *
 * Tham số đầu vào:
 *   @ManagerUserID uniqueidentifier : ID tài khoản Manager (để kiểm tra quyền)
 *   @EmployeeID    INT              : ID nhân viên cần vô hiệu hóa
 *
 * Kết quả trả về:
 *   Success, Message, EmployeeID, EmployeeName, BranchName, OldStatus, NewStatus
 *
 * Ví dụ:
 *   EXEC USP_MANAGER_DEACTIVATE_EMPLOYEE
 *       @ManagerUserID = 'GUID-CUA-MANAGER',
 *       @EmployeeID = 5;
 *
 * Lưu ý:
 *   - Không xóa dữ liệu, chỉ đổi status và khóa tài khoản
 *   - Manager không thể vô hiệu hóa chính mình
 *   - Manager không thể vô hiệu hóa Manager khác
 *   - Chỉ vô hiệu hóa nhân viên trong chi nhánh của mình
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE USP_MANAGER_DEACTIVATE_EMPLOYEE
    @ManagerUserID uniqueidentifier,
    @EmployeeID    INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ManagerBranchID     INT,
        @ManagerRoleName     NVARCHAR(100),
        @EmployeeBranchID    INT,
        @EmployeeUserID      uniqueidentifier,
        @EmployeeName        NVARCHAR(255),
        @EmployeeRoleName    NVARCHAR(100),
        @EmployeeOldStatus   NVARCHAR(50),
        @BranchName          NVARCHAR(255),
        @IsAccountActive     BIT;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @ManagerUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID Manager không được để trống.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
                   NULL AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @EmployeeID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID nhân viên không được để trống.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
                   NULL AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra Manager tồn tại và lấy thông tin
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
            SELECT 0 AS Success, N'Manager không tồn tại hoặc không phải là nhân viên.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
                   NULL AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @ManagerRoleName != N'Quản lý'
        BEGIN
            SELECT 0 AS Success, N'Chỉ Quản lý mới có quyền vô hiệu hóa nhân viên.' AS Message,
                   NULL AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
                   NULL AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra nhân viên tồn tại và lấy thông tin
         *-----------------------------------------------------*/
        SELECT 
            @EmployeeUserID = e.user_id,
            @EmployeeName = e.full_name,
            @EmployeeBranchID = e.branch_id,
            @EmployeeOldStatus = e.[status],
            @EmployeeRoleName = r.[name],
            @BranchName = b.[name],
            @IsAccountActive = a.is_active
        FROM employee e
        JOIN account a ON e.user_id = a.id
        JOIN [role] r ON a.role_id = r.id
        JOIN branch b ON e.branch_id = b.id
        WHERE e.id = @EmployeeID;

        IF @EmployeeUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Nhân viên không tồn tại.' AS Message,
                   @EmployeeID AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
                   NULL AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Kiểm tra quyền: Manager chỉ vô hiệu hóa nhân viên trong chi nhánh của mình
         *-----------------------------------------------------*/
        IF @EmployeeBranchID != @ManagerBranchID
        BEGIN
            SELECT 0 AS Success, 
                   N'Manager chỉ có thể vô hiệu hóa nhân viên trong chi nhánh của mình.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, @BranchName AS BranchName, 
                   @EmployeeOldStatus AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 5. Kiểm tra không được vô hiệu hóa chính mình
         *-----------------------------------------------------*/
        IF @EmployeeUserID = @ManagerUserID
        BEGIN
            SELECT 0 AS Success, N'Manager không thể vô hiệu hóa chính mình.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, @BranchName AS BranchName, 
                   @EmployeeOldStatus AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 6. Kiểm tra không được vô hiệu hóa Manager khác
         *-----------------------------------------------------*/
        IF @EmployeeRoleName = N'Quản lý'
        BEGIN
            SELECT 0 AS Success, N'Manager không thể vô hiệu hóa Manager khác.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, @BranchName AS BranchName, 
                   @EmployeeOldStatus AS OldStatus, NULL AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 7. Kiểm tra trạng thái hiện tại
         *-----------------------------------------------------*/
        IF @EmployeeOldStatus = N'Đã nghỉ việc'
        BEGIN
            SELECT 0 AS Success, 
                   N'Nhân viên "' + @EmployeeName + N'" đã ở trạng thái "Đã nghỉ việc" rồi.' AS Message,
                   @EmployeeID AS EmployeeID, @EmployeeName AS EmployeeName, @BranchName AS BranchName, 
                   @EmployeeOldStatus AS OldStatus, @EmployeeOldStatus AS NewStatus;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 8. Vô hiệu hóa tài khoản
         *-----------------------------------------------------*/
        UPDATE account
        SET is_active = 0
        WHERE id = @EmployeeUserID;

        /*------------------------------------------------------
         * 9. Cập nhật trạng thái nhân viên
         *-----------------------------------------------------*/
        UPDATE employee
        SET [status] = N'Đã nghỉ việc'
        WHERE id = @EmployeeID;

        /*------------------------------------------------------
         * 10. Commit và trả về kết quả
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Đã vô hiệu hóa nhân viên "' + @EmployeeName + N'" (' + @EmployeeRoleName 
            + N') tại chi nhánh "' + @BranchName + N'". Tài khoản đã bị khóa.' AS Message,
            @EmployeeID AS EmployeeID,
            @EmployeeName AS EmployeeName,
            @BranchName AS BranchName,
            @EmployeeOldStatus AS OldStatus,
            N'Đã nghỉ việc' AS NewStatus;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi vô hiệu hóa nhân viên: ' + ERROR_MESSAGE() AS Message,
            @EmployeeID AS EmployeeID, NULL AS EmployeeName, NULL AS BranchName, 
            NULL AS OldStatus, NULL AS NewStatus;
    END CATCH
END;
GO

/*
 * =================================================================================
 * STORED PROCEDURE BỔ SUNG - KÍCH HOẠT LẠI NHÂN VIÊN
 * =================================================================================
 */

/*
 * Manager kích hoạt lại nhân viên đã nghỉ việc (USP_MANAGER_REACTIVATE_EMPLOYEE)
 * 
 * Chức năng:
 *   - Đổi status từ "Đã nghỉ việc" → "Đang làm"
 *   - Mở khóa tài khoản (is_active = 1)
 *   - Chỉ kích hoạt nhân viên trong chi nhánh của mình
 *
 * Ví dụ:
 *   EXEC USP_MANAGER_REACTIVATE_EMPLOYEE
 *       @ManagerUserID = 'GUID-CUA-MANAGER',
 *       @EmployeeID = 5;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE USP_MANAGER_REACTIVATE_EMPLOYEE
    @ManagerUserID uniqueidentifier,
    @EmployeeID    INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ManagerBranchID     INT,
        @EmployeeBranchID    INT,
        @EmployeeUserID      uniqueidentifier,
        @EmployeeName        NVARCHAR(255),
        @EmployeeOldStatus   NVARCHAR(50),
        @BranchName          NVARCHAR(255);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Kiểm tra Manager
        SELECT @ManagerBranchID = branch_id
        FROM employee
        WHERE user_id = @ManagerUserID;

        IF @ManagerBranchID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Manager không tồn tại.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra nhân viên
        SELECT 
            @EmployeeUserID = e.user_id,
            @EmployeeName = e.full_name,
            @EmployeeBranchID = e.branch_id,
            @EmployeeOldStatus = e.[status],
            @BranchName = b.[name]
        FROM employee e
        JOIN branch b ON e.branch_id = b.id
        WHERE e.id = @EmployeeID;

        IF @EmployeeUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Nhân viên không tồn tại.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @EmployeeBranchID != @ManagerBranchID
        BEGIN
            SELECT 0 AS Success, N'Manager chỉ kích hoạt nhân viên trong chi nhánh của mình.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @EmployeeOldStatus != N'Đã nghỉ việc'
        BEGIN
            SELECT 0 AS Success, N'Chỉ có thể kích hoạt nhân viên đã nghỉ việc.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kích hoạt
        UPDATE account SET is_active = 1 WHERE id = @EmployeeUserID;
        UPDATE employee SET [status] = N'Đang làm' WHERE id = @EmployeeID;

        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Đã kích hoạt lại nhân viên "' + @EmployeeName + N'" tại "' + @BranchName + N'".' AS Message;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SELECT 0 AS Success, N'Lỗi: ' + ERROR_MESSAGE() AS Message;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO 2 STORED PROCEDURES ===';
PRINT N'1. USP_MANAGER_DEACTIVATE_EMPLOYEE - Vô hiệu hóa nhân viên';
PRINT N'2. USP_MANAGER_REACTIVATE_EMPLOYEE - Kích hoạt lại nhân viên';
GO