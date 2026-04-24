/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: THANH TOÁN HÓA ĐƠN
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Thanh toán hóa đơn (sp_Payment)
 * Chức năng:
 *   - Thanh toán một hóa đơn (invoice) và cập nhật trạng thái liên quan.
 *   - Cập nhật trạng thái:
 *       + invoice.status = N'Đã thanh toán'
 *       + court_booking.status = N'Đã thanh toán' (nếu invoice gắn với court_booking)
 *       + service_booking.status = N'Đã thanh toán' (nếu invoice gắn với service_booking)
 *   - Tích điểm thành viên bằng cách gọi sp_AddBonusPointForInvoice.
 *   - Ghi nhận nhân viên thu ngân xử lý thanh toán.
 *
 * Input:
 *   @InvoiceId      : Mã hóa đơn cần thanh toán (invoice.id)
 *   @PaymentMethod  : Phương thức thanh toán (N'Tiền mặt' / N'Chuyển khoản' / N'Thẻ' / N'Ví điện tử')
 *   @EmployeeId     : Mã nhân viên thu ngân xử lý thanh toán (employee.id, có thể NULL nếu thanh toán online)
 *
 * Output:
 *   - InvoiceId            : Mã hóa đơn
 *   - InvoiceAmount        : Số tiền hóa đơn
 *   - PaymentMethod        : Phương thức thanh toán
 *   - CustomerId           : Mã khách hàng
 *   - CustomerName         : Tên khách hàng
 *   - BonusPointBefore     : Điểm thưởng trước khi cộng
 *   - BonusPointAfter      : Điểm thưởng sau khi cộng
 *   - CourtBookingId       : Mã đặt sân (nếu có)
 *   - ServiceBookingId     : Mã đặt dịch vụ (nếu có)
 *
 * Quy ước business:
 *   1. Chỉ cho thanh toán hóa đơn có status = N'Chưa thanh toán'.
 *   2. Sau khi thanh toán thành công, tự động tích điểm cho khách hàng.
 *   3. Nếu invoice gắn với court_booking → cập nhật court_booking.status = N'Đã thanh toán'.
 *   4. Nếu invoice gắn với service_booking → cập nhật service_booking.status = N'Đã thanh toán'.
 *   5. Nếu có employee_id → ghi nhận nhân viên thu ngân xử lý.
 *
 * Ví dụ sử dụng:
 *   EXEC sp_Payment
 *       @InvoiceId     = 1,
 *       @PaymentMethod = N'Tiền mặt',
 *       @EmployeeId    = 5;
 */

CREATE OR ALTER PROCEDURE sp_Payment
(
    @InvoiceId     INT,
    @PaymentMethod NVARCHAR(50),
    @EmployeeId    INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @InvoiceStatus       NVARCHAR(50),
        @InvoiceAmount       DECIMAL(10, 2),
        @CourtBookingId      INT,
        @ServiceBookingId    INT,
        @CustomerId          INT,
        @CustomerName        NVARCHAR(255),
        @BonusPointBefore    INT,
        @BonusPointAfter     INT;

    BEGIN TRY
        BEGIN TRAN;

        /* =========================================================
         * BƯỚC 1: Kiểm tra hóa đơn tồn tại và trạng thái
         * ========================================================= */
        SELECT
            @InvoiceStatus    = I.[status],
            @InvoiceAmount    = I.total_amount,
            @CourtBookingId   = I.court_booking_id,
            @ServiceBookingId = I.service_booking_id
        FROM invoice I
        WHERE I.id = @InvoiceId;

        IF @InvoiceStatus IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy hóa đơn với mã đã cung cấp.', 16, 1);
        END

        IF @InvoiceStatus = N'Đã thanh toán'
        BEGIN
            RAISERROR (N'Hóa đơn này đã được thanh toán trước đó.', 16, 1);
        END

        IF @InvoiceStatus <> N'Chưa thanh toán'
        BEGIN
            RAISERROR (N'Hóa đơn không ở trạng thái "Chưa thanh toán", không thể thanh toán.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Kiểm tra phương thức thanh toán hợp lệ (R1112)
         * ========================================================= */
        IF (@PaymentMethod NOT IN (N'Tiền mặt', N'Chuyển khoản', N'Thẻ', N'Ví điện tử'))
        BEGIN
            RAISERROR (N'Phương thức thanh toán không hợp lệ. Chỉ chấp nhận: Tiền mặt / Chuyển khoản / Thẻ / Ví điện tử.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Kiểm tra nhân viên thu ngân (nếu có)
         * ========================================================= */
        IF @EmployeeId IS NOT NULL
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM employee WHERE id = @EmployeeId)
            BEGIN
                RAISERROR (N'Không tìm thấy nhân viên với mã đã cung cấp.', 16, 1);
            END
        END

        /* =========================================================
         * BƯỚC 4: Xác định khách hàng từ court_booking hoặc service_booking
         * ========================================================= */
        IF @CourtBookingId IS NOT NULL
        BEGIN
            SELECT
                @CustomerId = CB.customer_id
            FROM court_booking CB
            WHERE CB.id = @CourtBookingId;

            IF @CustomerId IS NULL
            BEGIN
                RAISERROR (N'Không xác định được khách hàng từ phiếu đặt sân.', 16, 1);
            END
        END
        ELSE IF @ServiceBookingId IS NOT NULL
        BEGIN
            SELECT
                @CustomerId = CB.customer_id
            FROM service_booking SB
            JOIN court_booking CB ON SB.court_booking_id = CB.id
            WHERE SB.id = @ServiceBookingId;

            IF @CustomerId IS NULL
            BEGIN
                RAISERROR (N'Không xác định được khách hàng từ phiếu đặt dịch vụ.', 16, 1);
            END
        END
        ELSE
        BEGIN
            RAISERROR (N'Hóa đơn không gắn với phiếu đặt sân hoặc phiếu đặt dịch vụ.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 5: Cập nhật trạng thái hóa đơn
         * ========================================================= */
        UPDATE invoice
        SET 
            [status]        = N'Đã thanh toán',
            payment_method  = @PaymentMethod,
            employee_id     = @EmployeeId
        WHERE id = @InvoiceId;

        /* =========================================================
         * BƯỚC 6: Cập nhật trạng thái court_booking (nếu có)
         * ========================================================= */
        IF @CourtBookingId IS NOT NULL
        BEGIN
            UPDATE court_booking
            SET [status] = N'Đã thanh toán'
            WHERE id = @CourtBookingId
              AND [status] <> N'Đã hủy';  -- Chỉ cập nhật nếu chưa hủy
        END

        /* =========================================================
         * BƯỚC 7: Cập nhật trạng thái service_booking (nếu có)
         * ========================================================= */
        IF @ServiceBookingId IS NOT NULL
        BEGIN
            UPDATE service_booking
            SET [status] = N'Đã thanh toán'
            WHERE id = @ServiceBookingId
              AND [status] <> N'Đã hủy';  -- Chỉ cập nhật nếu chưa hủy
        END

        /* =========================================================
         * BƯỚC 8: Tích điểm thành viên bằng cách gọi sp_AddBonusPointForInvoice
         * ========================================================= */
        -- Lấy điểm thưởng trước khi cộng
        SELECT @BonusPointBefore = bonus_point
        FROM customer
        WHERE id = @CustomerId;

        IF @BonusPointBefore IS NULL SET @BonusPointBefore = 0;

        -- Gọi SP tích điểm
        DECLARE @BonusResult TABLE
        (
            CustomerId       INT,
            CustomerName     NVARCHAR(255),
            InvoiceAmount    DECIMAL(10, 2),
            LoyaltyRate      DECIMAL(5, 2),
            BonusPointBefore INT,
            BonusPointAfter  INT
        );

        INSERT INTO @BonusResult
        EXEC sp_AddBonusPointForInvoice
            @CustomerId = @CustomerId,
            @InvoiceId  = @InvoiceId;

        SELECT
            @CustomerName     = CustomerName,
            @BonusPointAfter  = BonusPointAfter
        FROM @BonusResult;

        /* =========================================================
         * BƯỚC 9: Trả kết quả cho phía gọi
         * ========================================================= */
        SELECT
            @InvoiceId         AS InvoiceId,
            @InvoiceAmount     AS InvoiceAmount,
            @PaymentMethod     AS PaymentMethod,
            @CustomerId        AS CustomerId,
            @CustomerName      AS CustomerName,
            @BonusPointBefore  AS BonusPointBefore,
            @BonusPointAfter   AS BonusPointAfter,
            @CourtBookingId    AS CourtBookingId,
            @ServiceBookingId  AS ServiceBookingId;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        -- Rollback nếu transaction đang mở
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE
            @ErrMsg     NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrSev     INT            = ERROR_SEVERITY(),
            @ErrState   INT            = ERROR_STATE();

        RAISERROR (@ErrMsg, @ErrSev, @ErrState);
    END CATCH
END;
GO

