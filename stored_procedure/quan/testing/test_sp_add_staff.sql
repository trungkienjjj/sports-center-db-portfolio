USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_manager_create_staff
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
DECLARE @RoleKT_ID INT;
DECLARE @RoleQL_ID INT;
DECLARE @BranchHCM_ID INT;
DECLARE @BranchCT_ID INT;

-- Lấy Manager từ dữ liệu mẫu
SELECT @ManagerHCM_UserID = user_id 
FROM employee 
WHERE full_name = N'Nguyễn Văn A (QL)' AND branch_id = (SELECT id FROM branch WHERE [name] = N'VietSport TP.HCM');

SELECT @ManagerCT_UserID = user_id 
FROM employee 
WHERE full_name = N'Trần Văn F (QL)' AND branch_id = (SELECT id FROM branch WHERE [name] = N'VietSport Cần Thơ');

-- Lấy Role
SELECT @RoleLeTan_ID = id FROM [role] WHERE [name] = N'Lễ tân';
SELECT @RoleKT_ID = id FROM [role] WHERE [name] = N'Kỹ thuật';
SELECT @RoleQL_ID = id FROM [role] WHERE [name] = N'Quản lý';

-- Lấy Branch
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @BranchCT_ID = id FROM branch WHERE [name] = N'VietSport Cần Thơ';

-- Xóa dữ liệu test cũ
DELETE FROM employee WHERE email LIKE 'test.manager.create%@example.com';
DELETE FROM account WHERE username LIKE 'test.manager.create%';

PRINT N'  -> Manager HCM UserID: ' + CAST(@ManagerHCM_UserID AS NVARCHAR(50));
PRINT N'  -> Manager CT UserID: ' + CAST(@ManagerCT_UserID AS NVARCHAR(50));
PRINT N'  -> Role Lễ tân ID: ' + CAST(@RoleLeTan_ID AS NVARCHAR(10));
PRINT N'';

/* ================================================================
 * TEMP TABLE
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;
CREATE TABLE #Result (
    Success         BIT,
    Message         NVARCHAR(500),
    AccountID       UNIQUEIDENTIFIER,
    EmployeeID      INT,
    Username        VARCHAR(255),
    DefaultPassword NVARCHAR(100),
    BranchName      NVARCHAR(255)
);

/* ================================================================
 * TEST CASES
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_manager_create_staff';
PRINT N'============================================================';
PRINT N'';

/* TC01: Manager tạo nhân viên thành công cho chi nhánh của mình */
PRINT N'TC01 - Manager HCM tạo Lễ tân cho chi nhánh HCM';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.letan01',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Nhân Viên Test 01',
        @Gender = N'Nam',
        @DOB = '1995-05-15',
        @IDCardNumber = '079195888801',
        @Address = N'123 Test Address',
        @PhoneNumber = '0908888801',
        @Email = 'test.manager.create.letan01@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 500000,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND DefaultPassword = '12345678')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Manager tạo nhân viên với mật khẩu tùy chỉnh */
PRINT N'TC02 - Manager tạo nhân viên với mật khẩu tùy chỉnh';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.kt01',
        @PasswordPlain = 'CustomPass2025!',
        @RoleID = @RoleKT_ID,
        @FullName = N'Nhân Viên Test 02',
        @Gender = N'Nữ',
        @DOB = '1996-06-20',
        @IDCardNumber = '079196888802',
        @Address = N'456 Test Address',
        @PhoneNumber = '0908888802',
        @Email = 'test.manager.create.kt01@example.com',
        @BaseSalary = 9000000,
        @BaseAllowance = 800000,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND DefaultPassword = 'CustomPass2025!')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Manager cố tạo nhân viên cho chi nhánh khác */
PRINT N'TC03 - Manager HCM cố tạo nhân viên cho chi nhánh CT (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.fail01',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Fail Test',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888803',
        @Address = N'Address',
        @PhoneNumber = '0908888803',
        @Email = 'test.manager.create.fail01@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 0,
        @BranchID = @BranchCT_ID;  -- Chi nhánh khác!

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%chi nhánh của mình%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Manager cố tạo Manager khác (reject) */
PRINT N'TC04 - Manager cố tạo Manager khác (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.fail02',
        @RoleID = @RoleQL_ID,  -- Role Quản lý!
        @FullName = N'Fail Test Manager',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888804',
        @Address = N'Address',
        @PhoneNumber = '0908888804',
        @Email = 'test.manager.create.fail02@example.com',
        @BaseSalary = 15000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Lễ tân, Kỹ thuật, Thu ngân%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: ManagerUserID không tồn tại */
PRINT N'TC05 - ManagerUserID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = NEWID(),  -- UserID không tồn tại
        @Username = 'test.manager.create.fail03',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Fail Test',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888805',
        @Address = N'Address',
        @PhoneNumber = '0908888805',
        @Email = 'test.manager.create.fail03@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Manager không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Username trùng */
PRINT N'TC06 - Username trùng';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.letan01',  -- Trùng TC01
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Duplicate User',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888806',
        @Address = N'Address',
        @PhoneNumber = '0908888806',
        @Email = 'test.manager.create.dup@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Tên đăng nhập đã tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: CMND trùng */
PRINT N'TC07 - CMND trùng';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.cmnd',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Duplicate CMND',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079195888801',  -- Trùng TC01
        @Address = N'Address',
        @PhoneNumber = '0908888807',
        @Email = 'test.manager.create.cmnd@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%CMND%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Giới tính không hợp lệ */
PRINT N'TC08 - Giới tính không hợp lệ';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.gender',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Invalid Gender',
        @Gender = N'Unknown',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888808',
        @Address = N'Address',
        @PhoneNumber = '0908888808',
        @Email = 'test.manager.create.gender@example.com',
        @BaseSalary = 8000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Giới tính%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Lương âm */
PRINT N'TC09 - Lương âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerHCM_UserID,
        @Username = 'test.manager.create.salary',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Negative Salary',
        @Gender = N'Nam',
        @DOB = '1990-01-01',
        @IDCardNumber = '079190888809',
        @Address = N'Address',
        @PhoneNumber = '0908888809',
        @Email = 'test.manager.create.salary@example.com',
        @BaseSalary = -5000000,
        @BaseAllowance = 0,
        @BranchID = @BranchHCM_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Lương%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Manager khác chi nhánh tạo nhân viên thành công cho chi nhánh của mình */
PRINT N'TC10 - Manager CT tạo nhân viên cho chi nhánh CT';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_manager_create_staff
        @ManagerUserID = @ManagerCT_UserID,
        @Username = 'test.manager.create.ct01',
        @RoleID = @RoleLeTan_ID,
        @FullName = N'Nhân Viên CT Test',
        @Gender = N'Nữ',
        @DOB = '1997-07-07',
        @IDCardNumber = '079197888810',
        @Address = N'789 CT Address',
        @PhoneNumber = '0908888810',
        @Email = 'test.manager.create.ct01@example.com',
        @BaseSalary = 7500000,
        @BaseAllowance = 400000,
        @BranchID = @BranchCT_ID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND BranchName LIKE N'%Cần Thơ%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 10 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';
DELETE FROM employee WHERE email LIKE 'test.manager.create%@example.com';
DELETE FROM account WHERE username LIKE 'test.manager.create%';
DROP TABLE #Result;
PRINT N'=== HOÀN TẤT ===';
GO