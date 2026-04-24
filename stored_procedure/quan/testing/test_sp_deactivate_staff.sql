USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_manager_deactivate_employee & sp_manager_reactivate_employee
 * Người thực hiện : Bạn
 * Ngày            : 07/12/2025
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * CHUẨN BỊ DỮ LIỆU
 * ================================================================*/
PRINT N'=== PREPARE ===';

DECLARE @ManagerHCM_UserID uniqueidentifier;
DECLARE @ManagerCT_UserID uniqueidentifier;
DECLARE @RoleLeTan_ID INT;
DECLARE @BranchHCM_ID INT;
DECLARE @BranchCT_ID INT;
DECLARE @TestEmployeeID INT;
DECLARE @TestEmployee2ID INT;
DECLARE @TestAccountID uniqueidentifier;

-- Lấy Manager từ dữ liệu mẫu
SELECT @ManagerHCM_UserID = user_id 
FROM employee 
WHERE full_name = N'Nguyễn Văn A (QL)' AND branch_id = (SELECT id FROM branch WHERE [name] = N'VietSport TP.HCM');

SELECT @ManagerCT_UserID = user_id 
FROM employee 
WHERE full_name = N'Trần Văn F (QL)' AND branch_id = (SELECT id FROM branch WHERE [name] = N'VietSport Cần Thơ');

-- Lấy Role và Branch
SELECT @RoleLeTan_ID = id FROM [role] WHERE [name] = N'Lễ tân';
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @BranchCT_ID = id FROM branch WHERE [name] = N'VietSport Cần Thơ';

-- Xóa dữ liệu test cũ
DELETE FROM employee WHERE email LIKE 'test.deactivate%@example.com';
DELETE FROM account WHERE username LIKE 'test.deactivate%';

-- Tạo nhân viên test 1 (HCM) để vô hiệu hóa
INSERT INTO account(username, [password], role_id, is_active)
VALUES ('test.deactivate.emp01', 
        CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
        @RoleLeTan_ID, 1);

SET @TestAccountID = (SELECT id FROM account WHERE username = 'test.deactivate.emp01');

INSERT INTO employee(full_name, gender, dob, id_card_number, [address], phone_number, email,
                     [status], commission_rate, base_salary, base_allowance, user_id, branch_id)
VALUES (N'Nhân Viên Test Deactivate 01', N'Nam', '1995-01-01', '079195999901', N'Address Test',
        '0909999901', 'test.deactivate.emp01@example.com', N'Đang làm', 0.00, 8000000, 500000,
        @TestAccountID, @BranchHCM_ID);

SET @TestEmployeeID = SCOPE_IDENTITY();

-- Tạo nhân viên test 2 (CT) 
INSERT INTO account(username, [password], role_id, is_active)
VALUES ('test.deactivate.emp02', 
        CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
        @RoleLeTan_ID, 1);

INSERT INTO employee(full_name, gender, dob, id_card_number, [address], phone_number, email,
                     [status], commission_rate, base_salary, base_allowance, user_id, branch_id)
VALUES (N'Nhân Viên Test Deactivate 02', N'Nữ', '1996-02-02', '079196999902', N'Address Test',
        '0909999902', 'test.deactivate.emp02@example.com', N'Đang làm', 0.00, 8000000, 500000,
        (SELECT id FROM account WHERE username = 'test.deactivate.emp02'), @BranchCT_ID);

SET @TestEmployee2ID = SCOPE_IDENTITY();

PRINT N'  -> Manager HCM UserID: ' + CAST(@ManagerHCM_UserID AS NVARCHAR(50));
PRINT N'  -> Test Employee 1 ID: ' + CAST(@TestEmployeeID AS NVARCHAR(10)) + N' (HCM)';
PRINT N'  -> Test Employee 2 ID: ' + CAST(@TestEmployee2ID AS NVARCHAR(10)) + N' (CT)';
PRINT N'';

/* ================================================================
 * TEMP TABLE
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;
CREATE TABLE #Result (
    Success      BIT,
    Message      NVARCHAR(500),
    EmployeeID   INT,
    EmployeeName NVARCHAR(255),
    BranchName   NVARCHAR(255),
    OldStatus    NVARCHAR(50),
    NewStatus    NVARCHAR(50)
);

IF OBJECT_ID('tempdb..#Result2') IS NOT NULL DROP TABLE #Result2;
CREATE TABLE #Result2 (Success BIT, Message NVARCHAR(500));

/* ================================================================
 * TEST CASES - DEACTIVATE
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_manager_deactivate_employee';
PRINT N'============================================================';
PRINT N'';

/* TC01: Vô hiệu hóa nhân viên thành công */
PRINT N'TC01 - Manager HCM vô hiệu hóa nhân viên trong chi nhánh';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeID;

    -- Kiểm tra kết quả
    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND NewStatus = N'Đã nghỉ việc')
    BEGIN
        -- Verify trong DB
        DECLARE @DBStatus NVARCHAR(50);
        DECLARE @DBActive BIT;
        
        SELECT @DBStatus = e.[status], @DBActive = a.is_active
        FROM employee e
        JOIN account a ON e.user_id = a.id
        WHERE e.id = @TestEmployeeID;

        IF @DBStatus = N'Đã nghỉ việc' AND @DBActive = 0
            PRINT N'  => PASS (Status: Đã nghỉ việc, Account: Khóa)';
        ELSE
            PRINT N'  => FAIL (DB không cập nhật đúng)';
    END
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Vô hiệu hóa nhân viên đã nghỉ việc rồi */
PRINT N'TC02 - Vô hiệu hóa nhân viên đã nghỉ việc';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%đã ở trạng thái%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Manager HCM cố vô hiệu hóa nhân viên chi nhánh CT */
PRINT N'TC03 - Manager HCM cố vô hiệu hóa nhân viên chi nhánh CT (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployee2ID;  -- Nhân viên CT

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%chi nhánh của mình%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Manager cố vô hiệu hóa chính mình */
PRINT N'TC04 - Manager cố vô hiệu hóa chính mình (reject)';
BEGIN TRY
    DECLARE @ManagerHCM_EmpID INT;
    SELECT @ManagerHCM_EmpID = id FROM employee WHERE user_id = @ManagerHCM_UserID;

    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @ManagerHCM_EmpID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không thể vô hiệu hóa chính mình%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Manager cố vô hiệu hóa Manager khác */
PRINT N'TC05 - Manager HCM cố vô hiệu hóa Manager CT (reject)';
BEGIN TRY
    DECLARE @ManagerCT_EmpID INT;
    SELECT @ManagerCT_EmpID = id FROM employee WHERE user_id = @ManagerCT_UserID;

    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @ManagerCT_EmpID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Manager khác%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: EmployeeID không tồn tại */
PRINT N'TC06 - EmployeeID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = 99999;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: ManagerUserID không tồn tại */
PRINT N'TC07 - ManagerUserID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_deactivate_employee
        @ManagerUserID = NEWID(),
        @EmployeeID = @TestEmployeeID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Manager không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

