USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_manager_update_employee_profile
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
DECLARE @TestEmployeeHCM_ID INT;
DECLARE @TestEmployeeCT_ID INT;

-- Lấy Manager
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
DELETE FROM employee WHERE email LIKE 'test.update.emp%@example.com';
DELETE FROM account WHERE username LIKE 'test.update.emp%';

-- Tạo nhân viên test HCM
INSERT INTO account(username, [password], role_id, is_active)
VALUES ('test.update.emp.hcm', 
        CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
        @RoleLeTan_ID, 1);

INSERT INTO employee(full_name, gender, dob, id_card_number, [address], phone_number, email,
                     [status], commission_rate, base_salary, base_allowance, user_id, branch_id)
VALUES (N'Nhân Viên Test Update HCM', N'Nam', '1995-01-01', '079195777701', N'Address HCM',
        '0907777701', 'test.update.emp.hcm@example.com', N'Đang làm', 0.00, 8000000, 500000,
        (SELECT id FROM account WHERE username = 'test.update.emp.hcm'), @BranchHCM_ID);

SET @TestEmployeeHCM_ID = SCOPE_IDENTITY();

-- Tạo nhân viên test CT
INSERT INTO account(username, [password], role_id, is_active)
VALUES ('test.update.emp.ct', 
        CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
        @RoleLeTan_ID, 1);

INSERT INTO employee(full_name, gender, dob, id_card_number, [address], phone_number, email,
                     [status], commission_rate, base_salary, base_allowance, user_id, branch_id)
VALUES (N'Nhân Viên Test Update CT', N'Nữ', '1996-02-02', '079196777702', N'Address CT',
        '0907777702', 'test.update.emp.ct@example.com', N'Đang làm', 0.00, 7500000, 400000,
        (SELECT id FROM account WHERE username = 'test.update.emp.ct'), @BranchCT_ID);

SET @TestEmployeeCT_ID = SCOPE_IDENTITY();

PRINT N'  -> Manager HCM UserID: ' + CAST(@ManagerHCM_UserID AS NVARCHAR(50));
PRINT N'  -> Test Employee HCM ID: ' + CAST(@TestEmployeeHCM_ID AS NVARCHAR(10));
PRINT N'  -> Test Employee CT ID: ' + CAST(@TestEmployeeCT_ID AS NVARCHAR(10));
PRINT N'';

/* ================================================================
 * TEMP TABLE
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;
CREATE TABLE #Result (
    Success        BIT,
    Message        NVARCHAR(500),
    EmployeeID     INT,
    EmployeeName   NVARCHAR(255),
    UpdatedFields  NVARCHAR(MAX)
);

/* ================================================================
 * TEST CASES
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_manager_update_employee_profile';
PRINT N'============================================================';
PRINT N'';

/* TC01: Cập nhật 1 trường (PhoneNumber) */
PRINT N'TC01 - Cập nhật số điện thoại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @PhoneNumber = '0909888801';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND UpdatedFields LIKE '%PhoneNumber%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Cập nhật nhiều trường */
PRINT N'TC02 - Cập nhật nhiều trường (Email, Salary, Allowance)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @Email = 'new.email@example.com',
        @BaseSalary = 10000000,
        @BaseAllowance = 800000;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%Email%'
        AND UpdatedFields LIKE '%BaseSalary%'
        AND UpdatedFields LIKE '%BaseAllowance%'
    )
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Cập nhật status */
PRINT N'TC03 - Cập nhật trạng thái sang Nghỉ phép';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @Status = N'Nghỉ phép';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND UpdatedFields LIKE '%Status%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Manager HCM cố cập nhật nhân viên chi nhánh CT */
PRINT N'TC04 - Manager HCM cố cập nhật nhân viên CT (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeCT_ID,  -- Nhân viên CT
        @PhoneNumber = '0909999999';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%chi nhánh của mình%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Manager cố cập nhật Manager khác */
PRINT N'TC05 - Manager cố cập nhật Manager khác (reject)';
BEGIN TRY
    DECLARE @ManagerCT_EmpID INT;
    SELECT @ManagerCT_EmpID = id FROM employee WHERE user_id = @ManagerCT_UserID;

    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @ManagerCT_EmpID,
        @BaseSalary = 20000000;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Manager khác%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Phone trùng với nhân viên khác */
PRINT N'TC06 - Phone trùng (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @PhoneNumber = '0903000003';  -- Phone của nhân viên trong dữ liệu mẫu

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Số điện thoại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: Email trùng */
PRINT N'TC07 - Email trùng (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @Email = 'c.le@vietsport.com';  -- Email của nhân viên trong dữ liệu mẫu

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Email%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Status không hợp lệ */
PRINT N'TC08 - Status không hợp lệ (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @Status = N'Đang nghỉ dài hạn';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Trạng thái%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Lương âm */
PRINT N'TC09 - Lương âm (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @BaseSalary = -5000000;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Lương%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Không truyền tham số nào */
PRINT N'TC10 - Không truyền tham số nào (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Không có trường nào%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC11: EmployeeID không tồn tại */
PRINT N'TC11 - EmployeeID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = 99999,
        @PhoneNumber = '0909999999';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC12: Cập nhật tất cả trường */
PRINT N'TC12 - Cập nhật tất cả trường';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_update_employee_profile
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeHCM_ID,
        @FullName = N'Họ Tên Mới',
        @Address = N'Địa chỉ mới 123',
        @PhoneNumber = '0909888802',
        @Email = 'totally.new@example.com',
        @Status = N'Đang làm',
        @BaseSalary = 12000000,
        @BaseAllowance = 1000000;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%FullName%'
        AND UpdatedFields LIKE '%Address%'
        AND UpdatedFields LIKE '%PhoneNumber%'
        AND UpdatedFields LIKE '%Email%'
        AND UpdatedFields LIKE '%BaseSalary%'
    )
        PRINT N'  => PASS (Cập nhật 7 trường)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 12 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';
DELETE FROM employee WHERE id IN (@TestEmployeeHCM_ID, @TestEmployeeCT_ID);
DELETE FROM account WHERE username LIKE 'test.update.emp%';
DROP TABLE #Result;
PRINT N'=== HOÀN TẤT ===';
GO