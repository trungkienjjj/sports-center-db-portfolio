
/*
 * =================================================================================
 * STORED PROCEDURE BỔ SUNG - KÍCH HOẠT LẠI NHÂN VIÊN
 * =================================================================================
 */

/*
 * Manager kích hoạt lại nhân viên đã nghỉ việc (sp_reactivate_staff)
 * 
 * Chức năng:
 *   - Đổi status từ "Đã nghỉ việc" → "Đang làm"
 *   - Mở khóa tài khoản (is_active = 1)
 *   - Chỉ kích hoạt nhân viên trong chi nhánh của mình
 *
 * Ví dụ:
 *   EXEC sp_reactivate_staff
 *       @ManagerUserID = 'GUID-CUA-MANAGER',
 *       @EmployeeID = 5;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_reactivate_staff
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
PRINT N'1. sp_deactivate_staff - Vô hiệu hóa nhân viên';
PRINT N'2. sp_reactivate_staff - Kích hoạt lại nhân viên';
GO