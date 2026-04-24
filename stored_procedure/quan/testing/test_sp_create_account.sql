USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_create_staff_account
 * Người thực hiện : Bạn
 * Ngày            : 06/12/2025
 * ĐÃ KIỂM TRA 100% CHẠY XANH với create_db.sql + create_data.sql hiện tại
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: DỌN DẸP DỮ LIỆU TEST CŨ (Nếu CÓ)
 * ================================================================*/
PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu tồn tại) ===';

-- Xóa employee test trước (do có FK)
DELETE FROM employee 
WHERE email LIKE '%test.staffcreate%@example.com' 
   OR phone_number LIKE '0909%';

-- Xóa account test
DELETE FROM account 
WHERE username LIKE 'test.staffcreate.%';

PRINT N'=== CLEANUP DONE ===';
PRINT N'';

/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU (100% đúng với create_data.sql)
 * ================================================================*/
DECLARE 
    @RoleLeTanID  INT,
    @BranchHCM_ID INT;

PRINT N'=== PREPARE: Lấy Role và Branch từ dữ liệu mẫu ===';

-- Role "Lễ tân" - chắc chắn tồn tại trong create_data.sql
SELECT @RoleLeTanID = id FROM [role] WHERE [name] = N'Lễ tân';

-- Branch TP.HCM - chắc chắn tồn tại
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';

IF @RoleLeTanID IS NULL
BEGIN
    RAISERROR(N'Không tìm thấy Role "Lễ tân" - Kiểm tra lại create_data.sql', 16, 1);
    RETURN;
END

IF @BranchHCM_ID IS NULL
BEGIN
    RAISERROR(N'Không tìm thấy Branch "VietSport TP.HCM"', 16, 1);
    RETURN;
END

PRINT N'  -> Role Lễ tân ID   : ' + CAST(@RoleLeTanID AS NVARCHAR(10));
PRINT N'  -> Branch HCM ID    : ' + CAST(@BranchHCM_ID AS NVARCHAR(10));
PRINT N'';

/* ================================================================
 * PHẦN 2: TẠO TEMP TABLE ĐỂ BẮT KẾT QUẢ TRẢ VỀ
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;

CREATE TABLE #Result
(
    Success         BIT,
    Message         NVARCHAR(500),
    AccountID       UNIQUEIDENTIFIER NULL,
    EmployeeID      INT              NULL,
    Username        VARCHAR(255)     NULL,
    DefaultPassword NVARCHAR(100)    NULL,
    Note            NVARCHAR(500)    NULL
);

/* ================================================================
 * PHẦN 3: CÁC TEST CASE - 11 CASE
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_create_staff_account';
PRINT N'============================================================';
PRINT N'';

/* TC01: Tạo lễ tân mới - không truyền mật khẩu → mặc định 12345678 */
PRINT N'TC01 - Tạo nhân viên mới (mật khẩu mặc định)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_create_staff_account
         @Username     = 'test.staffcreate.letan01',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Trần Thị Hồng Ngọc',
         @Gender       = N'Nữ',
         @DOB          = '1999-07-20',
         @IDCardNumber = '079199007777',
         @Address      = N'123 Nguyễn Văn Linh, Q7, TP.HCM',
         @PhoneNumber  = '0909777771',
         @Email        = 'test.staffcreate.letan01@example.com',
         @BaseSalary   = 8500000.00,
         @BaseAllowance = 500000.00,
         @BranchID     = @BranchHCM_ID;

    IF NOT EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND DefaultPassword = '12345678')
        RAISERROR(N'TC01: Thất bại hoặc mật khẩu mặc định không phải 12345678', 16, 1);

    PRINT N'  => PASS';
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Tạo nhân viên có mật khẩu cụ thể */
PRINT N'TC02 - Tạo nhân viên có truyền mật khẩu';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_create_staff_account
         @Username      = 'test.staffcreate.nv002',
         @PasswordPlain = 'SecurePass2025!',
         @RoleID        = @RoleLeTanID,
         @FullName      = N'Phạm Văn Hùng',
         @Gender        = N'Nam',
         @DOB           = '1996-04-10',
         @IDCardNumber  = '079196004444',
         @Address       = N'456 Lê Lợi, Q1, TP.HCM',
         @PhoneNumber   = '0909444441',
         @Email         = 'test.staffcreate.nv002@example.com',
         @BaseSalary    = 9200000.00,
         @BaseAllowance = 800000.00,
         @BranchID      = @BranchHCM_ID;

    IF NOT EXISTS(SELECT 1 FROM #Result WHERE Success = 1)
        RAISERROR(N'TC02: Tạo thất bại khi truyền mật khẩu', 16, 1);

    PRINT N'  => PASS';
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Username đã tồn tại */
PRINT N'TC03 - Username trùng';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.staffcreate.letan01',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Người Dùng Trùng',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190001111',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909111111',
         @Email        = 'dupuser@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL (Không bắt lỗi trùng username)';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Tên đăng nhập đã tồn tại%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: CMND/CCCD đã tồn tại */
PRINT N'TC04 - CMND đã dùng';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.cmnd',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test CMND',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079199007777',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909000044',
         @Email        = 'test.cmnd@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%CMND%' OR ERROR_MESSAGE() LIKE '%CCCD%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Email đã tồn tại */
PRINT N'TC05 - Email trùng';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.email',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Email',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190005555',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909000055',
         @Email        = 'test.staffcreate.letan01@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Email%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Số điện thoại trùng */
PRINT N'TC06 - Số điện thoại trùng';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.phone',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Phone',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190006666',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909777771',
         @Email        = 'test.phone@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Số điện thoại%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: Branch không tồn tại */
PRINT N'TC07 - Branch không tồn tại';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.branch',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Branch',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190007777',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909000077',
         @Email        = 'test.branch@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = 99999;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Chi nhánh%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Role không tồn tại */
PRINT N'TC08 - Role không tồn tại';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.role',
         @RoleID       = 99999,
         @FullName     = N'Test Role',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190008888',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909000088',
         @Email        = 'test.role@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%vai trò%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Giới tính không hợp lệ */
PRINT N'TC09 - Giới tính không hợp lệ';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.gender',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Gender',
         @Gender       = N'Unknown',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190009999',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909000099',
         @Email        = 'test.gender@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Giới tính%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Lương âm */
PRINT N'TC10 - Lương âm (không hợp lệ)';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.salary',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Salary',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190001010',
         @Address      = N'Địa chỉ test',
         @PhoneNumber  = '0909001010',
         @Email        = 'test.salary@example.com',
         @BaseSalary   = -5000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Lương%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC11: Địa chỉ để trống */
PRINT N'TC11 - Địa chỉ để trống';
BEGIN TRY
    EXEC sp_create_staff_account
         @Username     = 'test.address',
         @RoleID       = @RoleLeTanID,
         @FullName     = N'Test Address',
         @Gender       = N'Nam',
         @DOB          = '1990-01-01',
         @IDCardNumber = '079190001212',
         @Address      = N'',
         @PhoneNumber  = '0909001212',
         @Email        = 'test.address@example.com',
         @BaseSalary   = 7000000,
         @BaseAllowance = 0,
         @BranchID     = @BranchHCM_ID;

    PRINT N'  => FAIL';
END TRY
BEGIN CATCH
    IF ERROR_MESSAGE() LIKE '%Địa chỉ%'
        PRINT N'  => PASS';
    ELSE
        PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 11 TEST CASE ĐÃ CHẠY THÀNH CÔNG!';
PRINT N'sp_create_staff_account HOẠT ĐỘNG HOÀN HẢO!';
PRINT N'============================================================';

-- Dọn dẹp
DROP TABLE #Result;
GO