/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: ĐĂNG KÝ TÀI KHOẢN KHÁCH HÀNG
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Đăng ký khách hàng mới (sp_RegisterCustomer)
 * Chức năng:
 *   - Tạo mới 1 tài khoản (account) với role là "Khách hàng/Member"
 *   - Tạo mới 1 bản ghi customer gắn với account đó
 *   - Mặc định:
 *       + customer_level = 'Thường'
 *       + bonus_point    = 0
 *
 * Input:
 *   @FullName    : Họ và tên
 *   @Email       : Email (dùng làm username + email khách hàng)
 *   @Dob         : Ngày sinh
 *   @PhoneNumber : Số điện thoại
 *   @Gender      : Giới tính (N'Nam' / N'Nữ' / N'Khác')
 *   @Password    : Mật khẩu 
 *
 * Output:
 *   - Trả về thông tin cơ bản của khách hàng vừa tạo:
 *       + CustomerId, AccountId, FullName, Email, PhoneNumber, LevelName, BonusPoint
 *
 * Ví dụ sử dụng:
 *   EXEC sp_RegisterCustomer
 *       @FullName    = N'Nguyễn Văn A',
 *       @Email       = 'nguyenvana@gmail.com',
 *       @Dob         = '1990-05-15',
 *       @PhoneNumber = '0901234567',
 *       @Gender      = N'Nam',
 *       @Password    = 'SecurePass123';
 */

CREATE OR ALTER PROCEDURE sp_RegisterCustomer
(
    @FullName    NVARCHAR(255),
    @Email       VARCHAR(255),
    @Dob         DATE,
    @PhoneNumber VARCHAR(20),
    @Gender      NVARCHAR(10),
    @Password    VARCHAR(500)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @RoleCustomerID    INT,
        @LevelThuongID     INT,
        @AccountID         UNIQUEIDENTIFIER,
        @CustomerID        INT,
        @TempIdCardNumber  VARCHAR(20),
        @DefaultAddress    NVARCHAR(500);

    BEGIN TRY
        BEGIN TRAN;

        /* =========================================================
         * BƯỚC 1: Kiểm tra dữ liệu đầu vào cơ bản
         * ========================================================= */

        -- Kiểm tra bắt buộc: FullName, Email, Phone, Dob, Gender, Password không được null
        IF (@FullName IS NULL OR LTRIM(RTRIM(@FullName)) = N'')
        BEGIN
            RAISERROR (N'Họ và tên không được để trống.', 16, 1);
        END

        IF (@Email IS NULL OR LTRIM(RTRIM(@Email)) = '')
        BEGIN
            RAISERROR (N'Email không được để trống.', 16, 1);
        END

        IF (@PhoneNumber IS NULL OR LTRIM(RTRIM(@PhoneNumber)) = '')
        BEGIN
            RAISERROR (N'Số điện thoại không được để trống.', 16, 1);
        END

        IF (@Dob IS NULL)
        BEGIN
            RAISERROR (N'Ngày sinh không được để trống.', 16, 1);
        END

        IF (@Gender NOT IN (N'Nam', N'Nữ', N'Khác'))
        BEGIN
            RAISERROR (N'Giới tính phải là Nam, Nữ hoặc Khác.', 16, 1);
        END

        IF (@Password IS NULL OR LTRIM(RTRIM(@Password)) = '')
        BEGIN
            RAISERROR (N'Mật khẩu không được để trống.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Lấy role_id và customer_level_id mặc định
         * ========================================================= */

        -- Role khách hàng/Member
        SELECT @RoleCustomerID = id
        FROM [role]
        WHERE [name] = N'Khách hàng/Member';

        IF @RoleCustomerID IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy Role "Khách hàng/Member". Kiểm tra lại dữ liệu bảng [role].', 16, 1);
        END

        -- Level "Thường"
        SELECT @LevelThuongID = id
        FROM customer_level
        WHERE [name] = N'Thường';

        IF @LevelThuongID IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy Customer Level "Thường". Kiểm tra lại dữ liệu bảng [customer_level].', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Validate thêm: Email format
         * ========================================================= */

        -- Validate định dạng email cơ bản
        IF @Email NOT LIKE '%_@__%.__%'
        BEGIN
            RAISERROR (N'Định dạng email không hợp lệ.', 16, 1);
        END

        -- Ngày sinh không được là ngày tương lai
        IF @Dob > CAST(GETDATE() AS DATE)
        BEGIN
            RAISERROR (N'Ngày sinh không hợp lệ (không thể là ngày tương lai).', 16, 1);
        END

        /* =========================================================
         * BƯỚC 4: Kiểm tra trùng lặp Email / Số điện thoại / Username
         * ========================================================= */

        -- Kiểm tra username (email) trên bảng account 
        IF EXISTS (SELECT 1 FROM account WHERE username = @Email)
        BEGIN
            RAISERROR (N'Email đã được sử dụng cho một tài khoản khác.', 16, 1);
        END

        -- Email phải duy nhất trên bảng customer
        IF EXISTS (SELECT 1 FROM customer WHERE email = @Email)
        BEGIN
            RAISERROR (N'Email đã tồn tại trong hệ thống.', 16, 1);
        END

        -- Phone phải duy nhất trên bảng customer
        IF EXISTS (SELECT 1 FROM customer WHERE phone_number = @PhoneNumber)
        BEGIN
            RAISERROR (N'Số điện thoại đã tồn tại trong hệ thống.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 4: Tạo Account mới cho khách hàng
         * ========================================================= */

        SET @AccountID = NEWID();

        INSERT INTO [account] ([id], [username], [password], [is_active], [role_id])
        VALUES (@AccountID, @Email, @Password, 1, @RoleCustomerID);

        /* =========================================================
         * BƯỚC 5: Tạo Customer mới gắn với Account
         * ========================================================= */

        -- Vì schema yêu cầu id_card_number & address NOT NULL nên set mặc định:
        SET @TempIdCardNumber = LEFT('TEMP-' + @PhoneNumber, 20);  -- đảm bảo không quá 20 ký tự
        SET @DefaultAddress   = N'Chưa cập nhật';

        INSERT INTO [customer]
        (
            [full_name],
            [dob],
            [gender],
            [id_card_number],
            [address],
            [phone_number],
            [email],
            [bonus_point],
            [customer_level_id],
            [user_id]
        )
        VALUES
        (
            @FullName,
            @Dob,
            @Gender,
            @TempIdCardNumber,
            @DefaultAddress,
            @PhoneNumber,
            @Email,
            0,                -- bonus_point mặc định = 0
            @LevelThuongID,   -- Level "Thường"
            @AccountID        -- FK sang account
        );

        SET @CustomerID = SCOPE_IDENTITY();

        /* =========================================================
         * BƯỚC 6: Trả kết quả cho phía gọi
         * ========================================================= */

        SELECT 
            C.id              AS CustomerId,
            A.id              AS AccountId,
            C.full_name       AS FullName,
            C.email           AS Email,
            C.phone_number    AS PhoneNumber,
            CL.[name]         AS CustomerLevel,
            C.bonus_point     AS BonusPoint,
            A.username        AS Username
        FROM customer C
        JOIN account A        ON C.user_id = A.id
        JOIN customer_level CL ON C.customer_level_id = CL.id
        WHERE C.id = @CustomerID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        -- Rollback nếu còn transaction mở
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE 
            @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrSeverity INT       = ERROR_SEVERITY(),
            @ErrState INT          = ERROR_STATE();

        RAISERROR (@ErrMsg, @ErrSeverity, @ErrState);
    END CATCH
END;
GO
