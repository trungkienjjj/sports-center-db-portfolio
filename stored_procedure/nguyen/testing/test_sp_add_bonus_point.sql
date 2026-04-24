/*
 * =================================================================
 * TEST SCRIPT - sp_AddBonusPointForInvoice
 * Người thực hiện : Nguyên (test)
 * Ngày            : 05/12/2025
 * Yêu cầu         :
 *   - Đã chạy: create_db.sql, create_constraints.sql, create_data.sql
 *   - Đã tạo:  sp_AddBonusPointForInvoice
 * =================================================================
 */

USE SportsCenterDB;
GO

SET NOCOUNT ON;

/* ================================================================
 * PHẦN 0: DỌN DẸP DỮ LIỆU TEST CŨ (NẾU CÓ)
 *   - Xóa các invoice / account / customer được tạo cho test lần trước
 * ================================================================*/

PRINT N'=== CLEANUP: Xóa dữ liệu test cũ (nếu có) ===';

-- Xóa refund_info gắn với invoice test (nếu có)
-- Invoice test được đánh dấu bằng total_amount = 50000.00 và status = 'Chưa thanh toán'
-- (hoặc có thể xóa trực tiếp bằng ID nếu được lưu từ test trước)
DELETE FROM refund_info
WHERE invoice_id IN (
    SELECT id FROM invoice 
    WHERE total_amount = 50000.00 
      AND status = N'Chưa thanh toán'
      AND payment_method = N'Tiền mặt'
);

-- Xóa invoice test "Chưa thanh toán" được tạo cho test
-- (total_amount = 50000.00, status = 'Chưa thanh toán' để phân biệt với invoice thật)
DELETE FROM invoice
WHERE total_amount = 50000.00 
  AND status = N'Chưa thanh toán'
  AND payment_method = N'Tiền mặt';

-- Xóa customer/account test
DECLARE @TmpTestAcc TABLE (id uniqueidentifier);

INSERT INTO @TmpTestAcc(id)
SELECT user_id
FROM customer
WHERE email LIKE 'test.addbonus.%@example.com';

DELETE FROM customer
WHERE email LIKE 'test.addbonus.%@example.com';

DELETE FROM account
WHERE id IN (SELECT id FROM @TmpTestAcc)
   OR username LIKE 'test.addbonus.%';

PRINT N'=== CLEANUP DONE ===';
PRINT N'';


/* ================================================================
 * PHẦN 1: CHUẨN BỊ DỮ LIỆU CẦN THIẾT
 *   - Lấy khách hàng mẫu (Trần Thị B - phone 0902000002)
 *   - Xác định 2 hóa đơn mẫu:
 *       + Hóa đơn đặt sân HCM (court_booking_id NOT NULL)
 *       + Hóa đơn dịch vụ (service_booking_id NOT NULL)
 *   - Tạo thêm 1 khách hàng khác để test "invoice không thuộc về khách"
 *   - Tạo thêm 1 hóa đơn "Chưa thanh toán" để test
 * ================================================================*/

DECLARE 
    @MainCustomerId           INT,
    @MainCustomerName         NVARCHAR(255),
    @OriginalBonusMain        INT,

    @CourtInvoiceId           INT,
    @ServiceInvoiceId         INT,
    @UnpaidInvoiceId          INT,

    @BookingCourtId           INT,

    @InvoiceAmountCourt       DECIMAL(10, 2),
    @InvoiceAmountService     DECIMAL(10, 2),
    @LoyaltyRateCourt         DECIMAL(5, 2),
    @LoyaltyRateService       DECIMAL(5, 2),

    @RoleCustomerID           INT,
    @LevelThuongID            INT,
    @OtherCustomerId          INT,
    @OtherAccountId           uniqueidentifier;


PRINT N'=== PREPARE: Lấy khách hàng mẫu & hóa đơn mẫu ===';

-- 1.1. Lấy khách hàng mẫu (từ create_data.sql)
SELECT 
    @MainCustomerId    = id,
    @MainCustomerName  = full_name,
    @OriginalBonusMain = bonus_point
FROM customer
WHERE phone_number = '0902000002';

IF @MainCustomerId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy khách hàng mẫu (phone = 0902000002). Kiểm tra lại dữ liệu mẫu.', 16, 1);
    RETURN;
END

-- 1.2. Lấy hóa đơn đặt sân HCM (court_booking_id NOT NULL)
SELECT TOP (1)
    @CourtInvoiceId     = I.id,
    @InvoiceAmountCourt = I.total_amount,
    @LoyaltyRateCourt   = B.loyalty_point_rate,
    @BookingCourtId     = CB.id
FROM invoice I
JOIN court_booking CB ON I.court_booking_id = CB.id
JOIN court CRT        ON CB.court_id        = CRT.id
JOIN branch B         ON CRT.branch_id      = B.id
WHERE CB.customer_id = @MainCustomerId
  AND I.status = N'Đã thanh toán'
ORDER BY I.id;

IF @CourtInvoiceId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy hóa đơn ĐÃ THANH TOÁN gắn với court_booking cho khách hàng mẫu.', 16, 1);
    RETURN;
END

-- 1.3. Lấy hóa đơn DỊCH VỤ (service_booking_id NOT NULL)
SELECT TOP (1)
    @ServiceInvoiceId       = I.id,
    @InvoiceAmountService   = I.total_amount,
    @LoyaltyRateService     = B2.loyalty_point_rate
FROM invoice I
JOIN service_booking SB  ON I.service_booking_id = SB.id
JOIN court_booking CB2   ON SB.court_booking_id  = CB2.id
JOIN court CRT2          ON CB2.court_id         = CRT2.id
JOIN branch B2           ON CRT2.branch_id       = B2.id
WHERE CB2.customer_id = @MainCustomerId
  AND I.status = N'Đã thanh toán'
ORDER BY I.id;

IF @ServiceInvoiceId IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy hóa đơn DỊCH VỤ ĐÃ THANH TOÁN cho khách hàng mẫu.', 16, 1);
    RETURN;
END

PRINT N'  -> Khách hàng mẫu: ' + @MainCustomerName + N' (ID = ' + CAST(@MainCustomerId AS NVARCHAR(20)) + N')';
PRINT N'  -> Court Invoice Id  : ' + CAST(@CourtInvoiceId AS NVARCHAR(20));
PRINT N'  -> Service Invoice Id: ' + CAST(@ServiceInvoiceId AS NVARCHAR(20));
PRINT N'';


PRINT N'=== PREPARE: Tạo khách hàng khác để test "invoice không thuộc về khách" ===';

-- 1.4. Lấy Role + Customer Level mặc định
SELECT @RoleCustomerID = id FROM [role] WHERE [name] = N'Khách hàng/Member';
SELECT @LevelThuongID  = id FROM customer_level WHERE [name] = N'Thường';

IF @RoleCustomerID IS NULL OR @LevelThuongID IS NULL
BEGIN
    RAISERROR (N'Không tìm thấy Role "Khách hàng/Member" hoặc Level "Thường".', 16, 1);
    RETURN;
END

-- 1.5. Tạo account + customer test
SET @OtherAccountId = NEWID();

INSERT INTO [account] ([id], [username], [password], [is_active], [role_id])
VALUES (@OtherAccountId, 'test.addbonus.customer2', 'dummy_password', 1, @RoleCustomerID);

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
    N'Khách Test AddBonus 2',
    '1999-01-01',
    N'Nam',
    'TESTADDPOINT00002',
    N'Địa chỉ test AddBonus',
    '0999000002',
    'test.addbonus.customer2@example.com',
    0,
    @LevelThuongID,
    @OtherAccountId
);

SET @OtherCustomerId = SCOPE_IDENTITY();

PRINT N'  -> Tạo khách hàng test ID = ' + CAST(@OtherCustomerId AS NVARCHAR(20));
PRINT N'';


PRINT N'=== PREPARE: Tạo hóa đơn "Chưa thanh toán" cho test ===';

-- 1.6. Tạo 1 invoice chưa thanh toán gắn với booking HCM
-- Lưu ý: payment_method phải là một trong: 'Tiền mặt', 'Chuyển khoản', 'Thẻ', 'Ví điện tử'
-- Với hóa đơn chưa thanh toán, dùng 'Tiền mặt' làm giá trị mặc định
INSERT INTO [invoice] ([total_amount], [payment_method], [status], [court_booking_id], [employee_id])
VALUES (50000.00, N'Tiền mặt', N'Chưa thanh toán', @BookingCourtId, NULL);

SET @UnpaidInvoiceId = SCOPE_IDENTITY();

PRINT N'  -> Unpaid Invoice Id: ' + CAST(@UnpaidInvoiceId AS NVARCHAR(20));
PRINT N'';


/* ================================================================
 * PHẦN 2: TẠO TEMP TABLE ĐỂ BẮT KẾT QUẢ TRẢ VỀ CỦA SP
 * ================================================================*/

IF OBJECT_ID('tempdb..#AddBonusResult') IS NOT NULL
    DROP TABLE #AddBonusResult;

CREATE TABLE #AddBonusResult
(
    CustomerId        INT,
    CustomerName      NVARCHAR(255),
    InvoiceAmount     DECIMAL(10, 2),
    LoyaltyRate       DECIMAL(5, 2),
    BonusPointBefore  INT,
    BonusPointAfter   INT
);


/* ================================================================
 * PHẦN 3: CÁC TEST CASE
 *   - TC01: Happy path - Hóa đơn sân (court_booking)
 *   - TC02: Happy path - Hóa đơn dịch vụ (service_booking)
 *   - TC03: CustomerId không tồn tại
 *   - TC04: InvoiceId không tồn tại
 *   - TC05: Hóa đơn không thuộc về khách
 *   - TC06: Hóa đơn chưa thanh toán
 * ================================================================*/

PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_AddBonusPointForInvoice';
PRINT N'============================================================';
PRINT N'';


/* ---------------------------------------------------------------
 * TC01: Happy path - Hóa đơn đặt sân (court_booking)
 *   - Expect: Cộng điểm đúng, trả về thông tin đúng
 * ---------------------------------------------------------------*/
PRINT N'TC01 - Happy path: Hóa đơn đặt sân (court_booking)';
BEGIN TRY
    DECLARE 
        @OldBonusTC1                INT,
        @ExpectedAddedCourt         INT,
        @ExpectedNewBonusAfterCourt INT,
        @R_CustId                   INT,
        @R_InvAmount                DECIMAL(10, 2),
        @R_LoyaltyRate              DECIMAL(5, 2),
        @R_Before                   INT,
        @R_After                    INT;

    TRUNCATE TABLE #AddBonusResult;

    -- Lấy điểm hiện tại trước khi cộng
    SELECT @OldBonusTC1 = bonus_point 
    FROM customer 
    WHERE id = @MainCustomerId;

    -- Tính điểm mong đợi
    SET @ExpectedAddedCourt         = CAST(@InvoiceAmountCourt * @LoyaltyRateCourt AS INT);
    SET @ExpectedNewBonusAfterCourt = @OldBonusTC1 + @ExpectedAddedCourt;

    -- Gọi SP
    INSERT INTO #AddBonusResult
    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @MainCustomerId,
         @InvoiceId  = @CourtInvoiceId;

    -- Kiểm tra số dòng trả về
    IF (SELECT COUNT(*) FROM #AddBonusResult) <> 1
        RAISERROR (N'TC01: SP không trả về đúng 1 dòng.', 16, 1);

    -- Lấy dữ liệu trả về
    SELECT TOP (1)
        @R_CustId      = CustomerId,
        @R_InvAmount   = InvoiceAmount,
        @R_LoyaltyRate = LoyaltyRate,
        @R_Before      = BonusPointBefore,
        @R_After       = BonusPointAfter
    FROM #AddBonusResult;

    IF @R_CustId <> @MainCustomerId
        RAISERROR (N'TC01: CustomerId trả về không đúng.', 16, 1);

    IF @R_InvAmount <> @InvoiceAmountCourt
        RAISERROR (N'TC01: InvoiceAmount trả về không đúng.', 16, 1);

    IF @R_LoyaltyRate <> @LoyaltyRateCourt
        RAISERROR (N'TC01: LoyaltyRate trả về không đúng.', 16, 1);

    IF @R_Before <> @OldBonusTC1
        RAISERROR (N'TC01: BonusPointBefore trả về không đúng.', 16, 1);

    IF @R_After <> @ExpectedNewBonusAfterCourt
        RAISERROR (N'TC01: BonusPointAfter trả về không đúng.', 16, 1);

    -- Kiểm tra giá trị thực trong bảng customer
    DECLARE @ActualBonusAfterCourt INT;
    SELECT @ActualBonusAfterCourt = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    IF @ActualBonusAfterCourt <> @ExpectedNewBonusAfterCourt
        RAISERROR (N'TC01: bonus_point trong bảng customer không đúng sau khi cập nhật.', 16, 1);

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC02: Happy path - Hóa đơn dịch vụ (service_booking)
 *   - Expect: Cộng điểm đúng tiếp tục từ kết quả TC01
 * ---------------------------------------------------------------*/
PRINT N'TC02 - Happy path: Hóa đơn dịch vụ (service_booking)';
BEGIN TRY
    DECLARE 
        @OldBonusTC2                   INT,
        @ExpectedAddedService          INT,
        @ExpectedNewBonusAfterService  INT,
        @R2_CustId                     INT,
        @R2_InvAmount                  DECIMAL(10, 2),
        @R2_LoyaltyRate                DECIMAL(5, 2),
        @R2_Before                     INT,
        @R2_After                      INT;

    TRUNCATE TABLE #AddBonusResult;

    -- Lấy điểm hiện tại trước khi cộng (sau TC01)
    SELECT @OldBonusTC2 = bonus_point 
    FROM customer 
    WHERE id = @MainCustomerId;

    SET @ExpectedAddedService         = CAST(@InvoiceAmountService * @LoyaltyRateService AS INT);
    SET @ExpectedNewBonusAfterService = @OldBonusTC2 + @ExpectedAddedService;

    INSERT INTO #AddBonusResult
    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @MainCustomerId,
         @InvoiceId  = @ServiceInvoiceId;

    IF (SELECT COUNT(*) FROM #AddBonusResult) <> 1
        RAISERROR (N'TC02: SP không trả về đúng 1 dòng.', 16, 1);

    SELECT TOP (1)
        @R2_CustId      = CustomerId,
        @R2_InvAmount   = InvoiceAmount,
        @R2_LoyaltyRate = LoyaltyRate,
        @R2_Before      = BonusPointBefore,
        @R2_After       = BonusPointAfter
    FROM #AddBonusResult;

    IF @R2_CustId <> @MainCustomerId
        RAISERROR (N'TC02: CustomerId trả về không đúng.', 16, 1);

    IF @R2_InvAmount <> @InvoiceAmountService
        RAISERROR (N'TC02: InvoiceAmount trả về không đúng.', 16, 1);

    IF @R2_LoyaltyRate <> @LoyaltyRateService
        RAISERROR (N'TC02: LoyaltyRate trả về không đúng.', 16, 1);

    IF @R2_Before <> @OldBonusTC2
        RAISERROR (N'TC02: BonusPointBefore trả về không đúng.', 16, 1);

    IF @R2_After <> @ExpectedNewBonusAfterService
        RAISERROR (N'TC02: BonusPointAfter trả về không đúng.', 16, 1);

    DECLARE @ActualBonusAfterService INT;
    SELECT @ActualBonusAfterService = bonus_point
    FROM customer
    WHERE id = @MainCustomerId;

    IF @ActualBonusAfterService <> @ExpectedNewBonusAfterService
        RAISERROR (N'TC02: bonus_point trong bảng customer không đúng sau khi cập nhật.', 16, 1);

    PRINT N'  => KẾT QUẢ: PASS.';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: FAIL.';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC03: CustomerId không tồn tại
 *   - Expect: Lỗi "Không tìm thấy khách hàng với ID đã cung cấp."
 * ---------------------------------------------------------------*/
PRINT N'TC03 - CustomerId không tồn tại';
BEGIN TRY
    DECLARE @FakeCustomerId INT;
    SELECT @FakeCustomerId = ISNULL(MAX(id), 0) + 100 FROM customer;

    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @FakeCustomerId,
         @InvoiceId  = @CourtInvoiceId;

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC04: InvoiceId không tồn tại
 *   - Expect: Lỗi "Không tìm thấy hóa đơn với ID đã cung cấp."
 * ---------------------------------------------------------------*/
PRINT N'TC04 - InvoiceId không tồn tại';
BEGIN TRY
    DECLARE @FakeInvoiceId INT;
    SELECT @FakeInvoiceId = ISNULL(MAX(id), 0) + 100 FROM invoice;

    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @MainCustomerId,
         @InvoiceId  = @FakeInvoiceId;

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC05: Hóa đơn không thuộc về khách
 *   - Expect: Lỗi "Hóa đơn không thuộc về khách hàng này, không thể tích điểm."
 * ---------------------------------------------------------------*/
PRINT N'TC05 - Hóa đơn không thuộc về khách';
BEGIN TRY
    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @OtherCustomerId,
         @InvoiceId  = @CourtInvoiceId;

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ---------------------------------------------------------------
 * TC06: Hóa đơn chưa thanh toán
 *   - Expect: Lỗi "Chỉ tích điểm cho hóa đơn đã thanh toán ..."
 * ---------------------------------------------------------------*/
PRINT N'TC06 - Hóa đơn chưa thanh toán';
BEGIN TRY
    EXEC sp_AddBonusPointForInvoice
         @CustomerId = @MainCustomerId,
         @InvoiceId  = @UnpaidInvoiceId;

    PRINT N'  => KẾT QUẢ: FAIL (Đáng ra phải báo lỗi nhưng lại chạy thành công).';
END TRY
BEGIN CATCH
    PRINT N'  => KẾT QUẢ: PASS (Nhận được lỗi như mong đợi).';
    PRINT N'     Message: ' + ERROR_MESSAGE();
END CATCH
PRINT N'------------------------------------------------------------';


/* ================================================================
 * PHẦN 4: KHÔI PHỤC LẠI ĐIỂM THƯỞNG BAN ĐẦU CHO KHÁCH HÀNG MẪU
 * ================================================================*/
PRINT N'=== RESTORE: Khôi phục bonus_point gốc cho khách hàng mẫu ===';

IF @MainCustomerId IS NOT NULL
BEGIN
    UPDATE customer
    SET bonus_point = @OriginalBonusMain
    WHERE id = @MainCustomerId;

    PRINT N'  -> bonus_point sau khi restore = ' + CAST(@OriginalBonusMain AS NVARCHAR(20));
END

PRINT N'';

/* ================================================================
 * PHẦN 5: XÓA HÓA ĐƠN TEST "CHƯA THANH TOÁN" ĐÃ TẠO
 * ================================================================*/
PRINT N'=== CLEANUP: Xóa hóa đơn test "Chưa thanh toán" ===';

IF @UnpaidInvoiceId IS NOT NULL
BEGIN
    -- Xóa refund_info nếu có (phòng trường hợp đã có refund)
    DELETE FROM refund_info
    WHERE invoice_id = @UnpaidInvoiceId;

    -- Xóa invoice test
    DELETE FROM invoice
    WHERE id = @UnpaidInvoiceId;

    PRINT N'  -> Đã xóa invoice test ID = ' + CAST(@UnpaidInvoiceId AS NVARCHAR(20));
END

PRINT N'============================================================';
PRINT N'KẾT THÚC TEST sp_AddBonusPointForInvoice';
PRINT N'============================================================';
