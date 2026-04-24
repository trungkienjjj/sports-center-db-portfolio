USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - USP_RESET_PASSWORD
 * Người thực hiện : Bạn
 * Ngày            : 06/12/2025
 * Test đầy đủ các trường hợp cho chức năng reset mật khẩu
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: CHUẨN BỊ DỮ LIỆU TEST
 * ================================================================*/
PRINT N'=== PREPARE: Tạo tài khoản test để reset mật khẩu ===';

DECLARE @TestRoleID INT;
DECLARE @TestBranchID INT;

-- Lấy Role và Branch từ dữ liệu mẫu
SELECT @TestRoleID = id FROM [role] WHERE [name] = N'Lễ tân';
SELECT @TestBranchID = id FROM branch WHERE [name] = N'VietSport TP.HCM';

-- Xóa dữ liệu test cũ (nếu có)
DELETE FROM employee WHERE email = 'test.reset.password@example.com';
DELETE FROM account WHERE username = 'test.reset.user';

-- Tạo tài khoản test để reset
DECLARE @TestAccountID UNIQUEIDENTIFIER;
DECLARE @TestEmployeeID INT;

-- Tạo account test (mật khẩu ban đầu là "OldPass123")
INSERT INTO account(username, [password], role_id, is_active)
VALUES (
    'test.reset.user',
    CONVERT(VARCHAR(128), HASHBYTES('SHA2_512', 'OldPass123' + CAST(NEWID() AS VARCHAR(36))), 2) + ':' + CAST(NEWID() AS VARCHAR(36)),
    @TestRoleID,
    1
);

SET @TestAccountID = (SELECT id FROM account WHERE username = 'test.reset.user');

-- Tạo employee liên kết
INSERT INTO employee(
    full_name, gender, dob, id_card_number, [address], phone_number, email,
    [status], commission_rate, base_salary, base_allowance, user_id, branch_id
)
VALUES(
    N'Nhân Viên Test Reset',
    N'Nam',
    '1990-01-01',
    '079190999999',
    N'Địa chỉ test',
    '0909999999',
    'test.reset.password@example.com',
    N'Đang làm',
    0.00,
    8000000,
    500000,
    @TestAccountID,
    @TestBranchID
);

SET @TestEmployeeID = SCOPE_IDENTITY();

PRINT N'  -> Đã tạo account: test.reset.user (mật khẩu: OldPass123)';
PRINT N'  -> Account ID: ' + CAST(@TestAccountID AS NVARCHAR(50));
PRINT N'';

/* ================================================================
 * PHẦN 1: TẠO TEMP TABLE ĐỂ BẮT KẾT QUẢ
 * ================================================================*/
IF OBJECT_ID('tempdb..#ResultReset') IS NOT NULL DROP TABLE #ResultReset;

CREATE TABLE #ResultReset
(
    Success     BIT,
    Message     NVARCHAR(500),
    Username    VARCHAR(255),
    NewPassword NVARCHAR(100),
    Note        NVARCHAR(500)
);

/* ================================================================
 * PHẦN 2: CÁC TEST CASE
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST USP_RESET_PASSWORD';
PRINT N'============================================================';
PRINT N'';

/* TC01: Reset về mật khẩu mặc định (12345678) */
PRINT N'TC01 - Reset về mật khẩu mặc định';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'test.reset.user';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 1 
        AND NewPassword = '12345678'
    )
        PRINT N'  => PASS (Mật khẩu mới: 12345678)';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL (Không reset được hoặc mật khẩu không phải 12345678)';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Reset về mật khẩu cụ thể */
PRINT N'TC02 - Reset về mật khẩu tùy chỉnh';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD 
        @Username = 'test.reset.user',
        @NewPasswordPlain = 'NewSecurePass2025!';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 1 
        AND NewPassword = 'NewSecurePass2025!'
    )
        PRINT N'  => PASS (Mật khẩu mới: NewSecurePass2025!)';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Username không tồn tại */
PRINT N'TC03 - Username không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'user.not.exist';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 0 
        AND Message LIKE N'%Tài khoản không tồn tại%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Username để trống */
PRINT N'TC04 - Username để trống';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = '';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 0 
        AND Message LIKE N'%Tên đăng nhập không được để trống%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Username NULL */
PRINT N'TC05 - Username NULL';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = NULL;

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 0 
        AND Message LIKE N'%Tên đăng nhập không được để trống%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Tài khoản bị vô hiệu hóa */
PRINT N'TC06 - Tài khoản bị vô hiệu hóa';
BEGIN TRY
    -- Vô hiệu hóa tài khoản test
    UPDATE account SET is_active = 0 WHERE username = 'test.reset.user';

    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'test.reset.user';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 0 
        AND Message LIKE N'%đã bị vô hiệu hóa%'
    )
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END

    -- Kích hoạt lại tài khoản để tiếp tục test
    UPDATE account SET is_active = 1 WHERE username = 'test.reset.user';
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
    -- Kích hoạt lại nếu bị lỗi
    UPDATE account SET is_active = 1 WHERE username = 'test.reset.user';
END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: Reset với mật khẩu có khoảng trắng đầu/cuối */
PRINT N'TC07 - Mật khẩu có khoảng trắng (tự động trim)';
BEGIN TRY
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD 
        @Username = 'test.reset.user',
        @NewPasswordPlain = '  TrimTest123  ';

    IF EXISTS(
        SELECT 1 FROM #ResultReset 
        WHERE Success = 1 
        AND NewPassword = 'TrimTest123'  -- Đã trim
    )
        PRINT N'  => PASS (Đã tự động trim khoảng trắng)';
    ELSE
    BEGIN
        SELECT * FROM #ResultReset;
        PRINT N'  => FAIL';
    END
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Kiểm tra mật khẩu đã được hash đúng cách */
PRINT N'TC08 - Kiểm tra mật khẩu được hash (có chứa Salt)';
BEGIN TRY
    -- Reset mật khẩu
    EXEC USP_RESET_PASSWORD 
        @Username = 'test.reset.user',
        @NewPasswordPlain = 'TestHash123';

    -- Kiểm tra password trong DB phải chứa dấu ":" (hash:salt format)
    DECLARE @HashedPassword VARCHAR(500);
    SELECT @HashedPassword = [password] 
    FROM account 
    WHERE username = 'test.reset.user';

    IF @HashedPassword LIKE '%:%' AND LEN(@HashedPassword) > 100
        PRINT N'  => PASS (Mật khẩu đã được hash với Salt)';
    ELSE
        PRINT N'  => FAIL (Mật khẩu không được hash đúng format)';
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Reset nhiều lần liên tiếp */
PRINT N'TC09 - Reset nhiều lần liên tiếp';
BEGIN TRY
    DECLARE @ResetCount INT = 0;
    
    -- Reset lần 1
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'test.reset.user', @NewPasswordPlain = 'Pass1';
    IF EXISTS(SELECT 1 FROM #ResultReset WHERE Success = 1) SET @ResetCount = @ResetCount + 1;

    -- Reset lần 2
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'test.reset.user', @NewPasswordPlain = 'Pass2';
    IF EXISTS(SELECT 1 FROM #ResultReset WHERE Success = 1) SET @ResetCount = @ResetCount + 1;

    -- Reset lần 3
    TRUNCATE TABLE #ResultReset;
    INSERT INTO #ResultReset
    EXEC USP_RESET_PASSWORD @Username = 'test.reset.user', @NewPasswordPlain = 'Pass3';
    IF EXISTS(SELECT 1 FROM #ResultReset WHERE Success = 1) SET @ResetCount = @ResetCount + 1;

    IF @ResetCount = 3
        PRINT N'  => PASS (Reset 3 lần liên tiếp thành công)';
    ELSE
        PRINT N'  => FAIL (Chỉ reset được ' + CAST(@ResetCount AS NVARCHAR(10)) + N'/3 lần)';
END TRY
BEGIN CATCH
    PRINT N'  => FAIL - ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 9 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * PHẦN 3: DỌN DẸP DỮ LIỆU TEST
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP: Xóa dữ liệu test ===';

DELETE FROM employee WHERE id = @TestEmployeeID;
DELETE FROM account WHERE id = @TestAccountID;
DROP TABLE #ResultReset;

PRINT N'  -> Đã xóa tài khoản test';
PRINT N'';
PRINT N'=== TEST HOÀN TẤT ===';
GO