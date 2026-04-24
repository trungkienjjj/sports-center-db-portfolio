USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_update_user_info
 * Người thực hiện : Bạn
 * Ngày            : 06/12/2025
 * Test đầy đủ các trường hợp cập nhật thông tin người dùng
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: CHUẨN BỊ DỮ LIỆU TEST
 * ================================================================*/
PRINT N'=== PREPARE: Tạo dữ liệu test ===';

DECLARE @TestRoleID INT;
DECLARE @TestBranchID INT;
DECLARE @TestBranch2ID INT;

-- Lấy Role và Branch từ dữ liệu mẫu
SELECT @TestRoleID = id FROM [role] WHERE [name] = N'Lễ tân';
SELECT @TestBranchID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @TestBranch2ID = id FROM branch WHERE [name] = N'VietSport Cần Thơ';

-- Xóa dữ liệu test cũ (nếu có)
DELETE FROM employee WHERE email IN ('test.update.emp@example.com', 'test.dup.phone@example.com', 'test.dup.email@example.com');
DELETE FROM customer WHERE email = 'test.update.cust@example.com';
DELETE FROM account WHERE username IN ('test.update.emp', 'test.update.cust', 'test.dup.phone', 'test.dup.email');

/* Tạo Employee test */
DECLARE @EmpAccountID UNIQUEIDENTIFIER;
DECLARE @EmpID INT;

INSERT INTO account(username, [password], role_id, is_active)
VALUES (
    'test.update.emp',
    CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
    @TestRoleID,
    1
);

SET @EmpAccountID = (SELECT id FROM account WHERE username = 'test.update.emp');

INSERT INTO employee(
    full_name, gender, dob, id_card_number, [address], phone_number, email,
    [status], commission_rate, base_salary, base_allowance, user_id, branch_id
)
VALUES(
    N'Nhân Viên Test Update',
    N'Nam',
    '1995-05-15',
    '079195888888',
    N'123 Test Street, HCM',
    '0908888888',
    'test.update.emp@example.com',
    N'Đang làm',
    0.00,
    8000000,
    500000,
    @EmpAccountID,
    @TestBranchID
);

SET @EmpID = SCOPE_IDENTITY();

/* Tạo Customer test */
DECLARE @CustAccountID UNIQUEIDENTIFIER;
DECLARE @CustID INT;
DECLARE @CustomerLevelID INT;

SELECT @CustomerLevelID = id FROM customer_level WHERE [name] = N'Thường';

INSERT INTO account(username, [password], role_id, is_active)
VALUES (
    'test.update.cust',
    CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
    (SELECT id FROM [role] WHERE [name] = N'Khách hàng/Member'),
    1
);

SET @CustAccountID = (SELECT id FROM account WHERE username = 'test.update.cust');

INSERT INTO customer(
    full_name, dob, gender, id_card_number, [address], phone_number, email,
    bonus_point, customer_level_id, user_id
)
VALUES(
    N'Khách Hàng Test Update',
    '1998-08-20',
    N'Nữ',
    '079198777777',
    N'456 Test Avenue, HCM',
    '0907777777',
    'test.update.cust@example.com',
    100,
    @CustomerLevelID,
    @CustAccountID
);

SET @CustID = SCOPE_IDENTITY();

/* Tạo dữ liệu để test trùng lặp */
-- Employee với phone và email khác để test trùng
INSERT INTO account(username, [password], role_id, is_active)
VALUES (
    'test.dup.phone',
    CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
    @TestRoleID,
    1
);

INSERT INTO employee(
    full_name, gender, dob, id_card_number, [address], phone_number, email,
    [status], commission_rate, base_salary, base_allowance, user_id, branch_id
)
VALUES(
    N'Nhân Viên Trùng Phone',
    N'Nữ',
    '1990-01-01',
    '079190666666',
    N'Address',
    '0906666666',  -- Phone này sẽ dùng để test trùng
    'test.dup.phone@example.com',
    N'Đang làm',
    0.00,
    8000000,
    500000,
    (SELECT id FROM account WHERE username = 'test.dup.phone'),
    @TestBranchID
);

INSERT INTO account(username, [password], role_id, is_active)
VALUES (
    'test.dup.email',
    CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'Pass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
    @TestRoleID,
    1
);

INSERT INTO employee(
    full_name, gender, dob, id_card_number, [address], phone_number, email,
    [status], commission_rate, base_salary, base_allowance, user_id, branch_id
)
VALUES(
    N'Nhân Viên Trùng Email',
    N'Nam',
    '1990-01-01',
    '079190555555',
    N'Address',
    '0905555555',
    'duplicate.email@example.com',  -- Email này sẽ dùng để test trùng
    N'Đang làm',
    0.00,
    8000000,
    500000,
    (SELECT id FROM account WHERE username = 'test.dup.email'),
    @TestBranchID
);

PRINT N'  -> Đã tạo Employee test: ' + CAST(@EmpAccountID AS NVARCHAR(50));
PRINT N'  -> Đã tạo Customer test: ' + CAST(@CustAccountID AS NVARCHAR(50));
PRINT N'';

/* ================================================================
 * PHẦN 1: TẠO TEMP TABLE ĐỂ BẮT KẾT QUẢ
 * ================================================================*/
IF OBJECT_ID('tempdb..#ResultUpdate') IS NOT NULL DROP TABLE #ResultUpdate;

CREATE TABLE #ResultUpdate
(
    Success        BIT,
    Message        NVARCHAR(500),
    UserID         UNIQUEIDENTIFIER,
    UpdatedFields  NVARCHAR(MAX)
);

/* ================================================================
 * PHẦN 2: TEST CASES CHO EMPLOYEE
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_update_user_info - EMPLOYEE';
PRINT N'============================================================';
PRINT N'';

/* TC01: Cập nhật một trường (Email) */
PRINT N'TC01 - Cập nhật email của Employee';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Email = 'new.email@example.com';

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 1 AND UpdatedFields LIKE '%Email%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Cập nhật nhiều trường cùng lúc */
PRINT N'TC02 - Cập nhật nhiều trường (Address, Phone, Salary)';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Address = N'789 New Address, District 1, HCM',
        @PhoneNumber = '0909999999',
        @BaseSalary = 10000000;

    IF EXISTS(
        SELECT 1 FROM #ResultUpdate 
        WHERE Success = 1 
        AND UpdatedFields LIKE '%Address%'
        AND UpdatedFields LIKE '%PhoneNumber%'
        AND UpdatedFields LIKE '%BaseSalary%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Chuyển chi nhánh */
PRINT N'TC03 - Chuyển chi nhánh Employee';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @BranchID = @TestBranch2ID;

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 1 AND UpdatedFields LIKE '%Branch%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Cập nhật trạng thái */
PRINT N'TC04 - Cập nhật trạng thái Employee';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Status = N'Nghỉ phép';

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 1 AND UpdatedFields LIKE '%Status%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Cập nhật giới tính và ngày sinh */
PRINT N'TC05 - Cập nhật giới tính và ngày sinh';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Gender = N'Nữ',
        @DOB = '1996-06-20';

    IF EXISTS(
        SELECT 1 FROM #ResultUpdate 
        WHERE Success = 1 
        AND UpdatedFields LIKE '%Gender%'
        AND UpdatedFields LIKE '%DOB%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* ================================================================
 * PHẦN 3: TEST CASES CHO CUSTOMER
 * ================================================================*/
PRINT N'';
PRINT N'============================================================';
PRINT N'TEST sp_update_user_info - CUSTOMER';
PRINT N'============================================================';
PRINT N'';

/* TC06: Cập nhật thông tin Customer */
PRINT N'TC06 - Cập nhật địa chỉ và email Customer';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @CustAccountID,
        @Address = N'999 Customer New Address',
        @Email = 'customer.new@example.com';

    IF EXISTS(
        SELECT 1 FROM #ResultUpdate 
        WHERE Success = 1 
        AND UpdatedFields LIKE '%Address%'
        AND UpdatedFields LIKE '%Email%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* ================================================================
 * PHẦN 4: TEST CASES VALIDATION
 * ================================================================*/
PRINT N'';
PRINT N'============================================================';
PRINT N'TEST VALIDATION';
PRINT N'============================================================';
PRINT N'';

/* TC07: UserID không tồn tại */
PRINT N'TC07 - UserID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = NEWID(),
        @Email = 'test@example.com';

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%không tồn tại%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Giới tính không hợp lệ */
PRINT N'TC08 - Giới tính không hợp lệ';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Gender = N'Unknown';

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Giới tính%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Trạng thái không hợp lệ */
PRINT N'TC09 - Trạng thái không hợp lệ';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Status = N'Invalid Status';

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Trạng thái%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Lương âm */
PRINT N'TC10 - Lương âm';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @BaseSalary = -5000000;

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Lương%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC11: Chi nhánh không tồn tại */
PRINT N'TC11 - Chi nhánh không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @BranchID = 99999;

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Chi nhánh%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC12: Số điện thoại trùng */
PRINT N'TC12 - Số điện thoại trùng với Employee khác';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @PhoneNumber = '0906666666';  -- Phone của test.dup.phone

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Số điện thoại%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC13: Email trùng */
PRINT N'TC13 - Email trùng với Employee khác';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @Email = 'duplicate.email@example.com';  -- Email của test.dup.email

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Email%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC14: Không truyền tham số nào (không cập nhật gì) */
PRINT N'TC14 - Không truyền tham số nào để cập nhật';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID;

    IF EXISTS(SELECT 1 FROM #ResultUpdate WHERE Success = 0 AND Message LIKE N'%Không có trường nào%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC15: Cập nhật tất cả trường của Employee */
PRINT N'TC15 - Cập nhật toàn bộ thông tin Employee';
BEGIN TRY
    TRUNCATE TABLE #ResultUpdate;
    INSERT INTO #ResultUpdate
    EXEC sp_update_user_info
        @UserID = @EmpAccountID,
        @FullName = N'Họ Tên Mới Hoàn Toàn',
        @Gender = N'Nam',
        @DOB = '1997-07-07',
        @IDCardNumber = '079197111111',
        @Address = N'Địa chỉ mới hoàn toàn',
        @PhoneNumber = '0901111111',
        @Email = 'totally.new@example.com',
        @Status = N'Đang làm',
        @BaseSalary = 15000000,
        @BaseAllowance = 2000000,
        @BranchID = @TestBranchID;

    IF EXISTS(
        SELECT 1 FROM #ResultUpdate 
        WHERE Success = 1 
        AND UpdatedFields LIKE '%FullName%'
        AND UpdatedFields LIKE '%BaseSalary%'
    )
        PRINT N'  => PASS (Cập nhật 11 trường)';
    ELSE
    BEGIN
        SELECT * FROM #ResultUpdate;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 15 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * PHẦN 5: DỌN DẸP DỮ LIỆU TEST
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP: Xóa dữ liệu test ===';

DELETE FROM employee WHERE id = @EmpID OR email IN ('test.dup.phone@example.com', 'test.dup.email@example.com');
DELETE FROM customer WHERE id = @CustID;
DELETE FROM account WHERE id IN (@EmpAccountID, @CustAccountID) 
    OR username IN ('test.dup.phone', 'test.dup.email');
DROP TABLE #ResultUpdate;

PRINT N'  -> Đã xóa dữ liệu test';
PRINT N'';
PRINT N'=== TEST HOÀN TẤT ===';
GO