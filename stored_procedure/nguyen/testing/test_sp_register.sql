/*
 * =================================================================
 * TEST SCRIPT - sp_RegisterCustomer
 * Người thực hiện : Nguyên (test)
 * Ngày            : 05/12/2025
 * Yêu cầu         :
 *   - Đã chạy: create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:  sp_RegisterCustomer
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: DỌN DẸP DỮ LIỆU TEST CŨ (NẾU CÓ)
 *  - Chỉ xóa những bản ghi có email/username bắt đầu bằng 'test.sp_register'
 * ================================================================*/

PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

-- Xóa customer test trước (vì có FK tới account)
DELETE FROM [customer]
WHERE [email] LIKE 'test.sp_register.%@example.com';

-- Xóa account test
DELETE FROM [account]
WHERE [username] LIKE 'test.sp_register.%@example.com';

PRINT N'=== CLEANUP DONE ===';
PRINT N'';
/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU ĐẶC BIỆT CHO TEST
 *  - Tạo 1 account với username là email để test case trùng username
 * ================================================================*/

PRINT N'=== PREPARE: Tạo account giả để test trùng username (account.username) ===';

DECLARE @AnyRoleID INT;

-- Lấy 1 role bất kỳ (vd: Quản lý) để tạo account test
SELECT @AnyRoleID = id
FROM [role]
WHERE [name] = N'Quản lý';

IF @AnyRoleID IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy role "Quản lý" để tạo account test. Kiểm tra lại dữ liệu.', 16, 1);
    RETURN;
END

-- Account này chỉ dùng để test "Email đã được sử dụng cho một tài khoản khác."
IF NOT EXISTS (SELECT 1 FROM [account] WHERE [username] = 'dup.sp_register@example.com')
BEGIN
    INSERT INTO [account] ([username], [password], [role_id])
    VALUES ('dup.sp_register@example.com', 'dummy_hash_for_test', @AnyRoleID);
END

PRINT N'=== PREPARE DONE ===';
PRINT N'';
/* ================================================================
 * PHẦN 2: CÁC TEST CASE CHO sp_RegisterCustomer
 *  - TC01: Đăng ký hợp lệ (Happy path)
 *  - TC02: Thiếu FullName
 *  - TC03: Thiếu Email
 *  - TC04: Thiếu PhoneNumber
 *  - TC05: Thiếu Dob
 *  - TC06: Thiếu Password
 *  - TC07: Gender không hợp lệ
 *  - TC08: Định dạng Email không hợp lệ
 *  - TC09: Dob là ngày tương lai
 *  - TC10: Email trùng trên bảng account (username)
 *  - TC11: Email trùng trên bảng customer (dùng data mẫu: b.tran@gmail.com)
 *  - TC12: Số điện thoại trùng trên bảng customer (dùng data mẫu: 0902000002)
 * ================================================================*/

PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_RegisterCustomer';
PRINT N'============================================================';
PRINT N'';


/* ---------------------------------------------------------------
 * TC01: Đăng ký khách hàng hợp lệ (Happy path)
 * Expect: THÀNH CÔNG, trả về bản ghi khách hàng mới
 * ---------------------------------------------------------------*/
PRINT N'TC01 - Happy path: Đăng ký hợp lệ';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 01',
         @Email       = 'test.sp_register.01@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000001',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: PASS (Thủ tục thực thi thành công).';
    PRINT N'     Kiểm tra lại kết quả ở Result Grid (CustomerLevel = "Thường", Role = "Khách hàng/Member").';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL (KHÔNG mong đợi lỗi).';
    PRINT N'     Lỗi: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC02: Thiếu FullName
 * Expect: Lỗi "Họ và tên không được để trống."
 * ---------------------------------------------------------------*/
PRINT N'TC02 - Thiếu FullName';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'',   -- không hợp lệ
         @Email       = 'test.sp_register.02@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000002',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC03: Thiếu Email
 * Expect: Lỗi "Email không được để trống."
 * ---------------------------------------------------------------*/
PRINT N'TC03 - Thiếu Email';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 03',
         @Email       = '',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000003',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC04: Thiếu PhoneNumber
 * Expect: Lỗi "Số điện thoại không được để trống."
 * ---------------------------------------------------------------*/
PRINT N'TC04 - Thiếu PhoneNumber';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 04',
         @Email       = 'test.sp_register.04@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC05: Thiếu Dob
 * Expect: Lỗi "Ngày sinh không được để trống."
 * ---------------------------------------------------------------*/
PRINT N'TC05 - Thiếu Dob';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 05',
         @Email       = 'test.sp_register.05@example.com',
         @Dob         = NULL,  -- không hợp lệ
         @PhoneNumber = '0909000005',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC06: Thiếu Password
 * Expect: Lỗi "Mật khẩu không được để trống."
 * ---------------------------------------------------------------*/
PRINT N'TC06 - Thiếu Password';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 06',
         @Email       = 'test.sp_register.06@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000006',
         @Gender      = N'Nam',
         @Password    = '';  -- không hợp lệ

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC07: Gender không hợp lệ
 * Expect: Lỗi "Giới tính phải là Nam, Nữ hoặc Khác."
 * ---------------------------------------------------------------*/
PRINT N'TC07 - Gender không hợp lệ';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 07',
         @Email       = 'test.sp_register.07@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000007',
         @Gender      = N'Giới tính lạ',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC08: Định dạng Email không hợp lệ
 * Expect: Lỗi "Định dạng email không hợp lệ."
 * ---------------------------------------------------------------*/
PRINT N'TC08 - Định dạng Email không hợp lệ';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 08',
         @Email       = 'email_sai_format', -- không có @
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000008',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC09: Dob là ngày tương lai
 * Expect: Lỗi "Ngày sinh không hợp lệ (không thể là ngày tương lai)."
 * ---------------------------------------------------------------*/
PRINT N'TC09 - Dob là ngày tương lai';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 09',
         @Email       = 'test.sp_register.09@example.com',
         @Dob         = '2100-01-01', -- tương lai
         @PhoneNumber = '0909000009',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC10: Email trùng trên bảng account (username)
 *  - Đã chuẩn bị account có username = 'dup.sp_register@example.com' ở PHẦN 1
 * Expect: Lỗi "Email đã được sử dụng cho một tài khoản khác."
 * ---------------------------------------------------------------*/
PRINT N'TC10 - Email trùng trên bảng account (username)';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 10',
         @Email       = 'dup.sp_register@example.com', -- trùng username của account đã tạo
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000010',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC11: Email trùng trên bảng customer
 *  - Dùng email mẫu đã có trong create_data.sql: 'b.tran@gmail.com'
 * Expect: Lỗi "Email đã tồn tại trong hệ thống."
 * ---------------------------------------------------------------*/
PRINT N'TC11 - Email trùng trên bảng customer (dùng data mẫu b.tran@gmail.com)';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 11',
         @Email       = 'b.tran@gmail.com', -- đã tồn tại trong bảng customer
         @Dob         = '1990-01-01',
         @PhoneNumber = '0909000011',
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC12: Số điện thoại trùng trên bảng customer
 *  - Dùng phone mẫu đã có: '0902000002'
 * Expect: Lỗi "Số điện thoại đã tồn tại trong hệ thống."
 * ---------------------------------------------------------------*/
PRINT N'TC12 - Phone trùng trên bảng customer (dùng data mẫu 0902000002)';
BEGIN TRY
    EXEC sp_RegisterCustomer
         @FullName    = N'Nguyễn Test 12',
         @Email       = 'test.sp_register.12@example.com',
         @Dob         = '1990-01-01',
         @PhoneNumber = '0902000002', -- đã tồn tại trong bảng customer
         @Gender      = N'Nam',
         @Password    = 'Test@123';

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


PRINT N'';
PRINT N'============================================================';
PRINT N'KẾT THÚC TEST sp_RegisterCustomer';
PRINT N'============================================================';
