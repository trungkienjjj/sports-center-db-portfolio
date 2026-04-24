/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: TÍCH ĐIỂM THÀNH VIÊN
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Tích điểm thành viên theo hóa đơn (sp_AddBonusPointForInvoice)
 * Chức năng:
 *   - Tích điểm thành viên cho 1 khách hàng dựa trên 1 hóa đơn cụ thể.
 *   - Điều kiện:
 *       + Hóa đơn phải có status = N'Đã thanh toán'
 *       + Hóa đơn phải thuộc về đúng khách hàng truyền vào
 *   - Công thức:
 *       + AddedBonus = loyalty_point_rate * invoice.total_amount (CAST về INT)
 *       + loyalty_point_rate lấy từ bảng [branch] của chi nhánh tương ứng
 *       + bonus_point mới = bonus_point cũ + AddedBonus
 *
 * Input:
 *   @CustomerId : id khách hàng (bảng [customer])
 *   @InvoiceId  : id hóa đơn (bảng [invoice])
 *
 * Output:
 *   - CustomerId        : Mã khách hàng
 *   - CustomerName      : Tên khách hàng
 *   - InvoiceAmount     : Số tiền của hóa đơn
 *   - LoyaltyRate       : Tỷ lệ tích điểm từ branch
 *   - BonusPointBefore  : Điểm thưởng trước khi cộng
 *   - BonusPointAfter   : Điểm thưởng sau khi cộng
 *
 * Lưu ý:
 *   - SP này dùng loyalty_point_rate từ bảng [branch] của chi nhánh tương ứng với hóa đơn.
 *   - Branch được xác định từ court_booking (nếu invoice gắn với court) hoặc từ service_booking → court_booking (nếu invoice gắn với service).
 *   - Nếu gọi nhiều lần cho cùng 1 hóa đơn, điểm sẽ bị cộng nhiều lần (cần quy ước business khi sử dụng).
 *
 * Ví dụ sử dụng:
 *   EXEC sp_AddBonusPointForInvoice
 *       @CustomerId = 1,
 *       @InvoiceId  = 5;
 */

CREATE OR ALTER PROCEDURE sp_AddBonusPointForInvoice
(
    @CustomerId INT,
    @InvoiceId  INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @InvoiceAmount     DECIMAL(10, 2),
        @InvoiceStatus     NVARCHAR(50),
        @ActualCustomerId  INT,
        @BranchId          INT,
        @LoyaltyRate       DECIMAL(5, 2),
        @OldBonus          INT,
        @AddedBonus        INT,
        @NewBonus          INT;

    BEGIN TRY
        BEGIN TRAN;

        /* =========================================================
         * BƯỚC 1: Kiểm tra khách hàng có tồn tại hay không
         * ========================================================= */
        IF NOT EXISTS (SELECT 1 FROM customer WHERE id = @CustomerId)
        BEGIN
            RAISERROR (N'Không tìm thấy khách hàng với ID đã cung cấp.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Xác định hóa đơn, khách hàng thực tế và branch_id
         *
         * Hóa đơn có thể gắn với:
         *   - court_booking_id (đặt sân)
         *   - service_booking_id (dịch vụ kèm theo, liên kết ngược về court_booking)
         * Dùng COALESCE để lấy đúng customer_id và branch_id:
         *   + Nếu là hóa đơn sân  → lấy từ court_booking.customer_id và court.branch_id
         *   + Nếu là hóa đơn DV   → lấy từ court_booking của service_booking đó
         * ========================================================= */

        ;WITH InvoiceInfo AS
        (
            SELECT
                I.id           AS InvoiceId,
                I.total_amount AS InvoiceAmount,
                I.[status]     AS InvoiceStatus,
                COALESCE(CB.customer_id, CB2.customer_id) AS CustomerId,
                COALESCE(CRT.branch_id, CRT2.branch_id) AS BranchId
            FROM invoice I
            LEFT JOIN court_booking CB
                ON I.court_booking_id = CB.id
            LEFT JOIN court CRT
                ON CB.court_id = CRT.id
            LEFT JOIN service_booking SB
                ON I.service_booking_id = SB.id
            LEFT JOIN court_booking CB2
                ON SB.court_booking_id = CB2.id
            LEFT JOIN court CRT2
                ON CB2.court_id = CRT2.id
            WHERE I.id = @InvoiceId
        )
        SELECT
            @InvoiceAmount    = InvoiceAmount,
            @InvoiceStatus    = InvoiceStatus,
            @ActualCustomerId = CustomerId,
            @BranchId         = BranchId
        FROM InvoiceInfo;

        -- Kiểm tra tồn tại hóa đơn
        IF @InvoiceAmount IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy hóa đơn với ID đã cung cấp.', 16, 1);
        END

        -- Kiểm tra hóa đơn có xác định được khách hàng hay không
        IF @ActualCustomerId IS NULL
        BEGIN
            RAISERROR (N'Không xác định được khách hàng của hóa đơn. Kiểm tra lại liên kết court_booking / service_booking.', 16, 1);
        END

        -- Kiểm tra hóa đơn có thuộc về khách hàng đầu vào không
        IF @ActualCustomerId <> @CustomerId
        BEGIN
            RAISERROR (N'Hóa đơn không thuộc về khách hàng này, không thể tích điểm.', 16, 1);
        END

        -- Chỉ tích điểm khi hóa đơn đã thanh toán
        IF @InvoiceStatus <> N'Đã thanh toán'
        BEGIN
            RAISERROR (N'Chỉ tích điểm cho hóa đơn đã thanh toán (status = N''Đã thanh toán'').', 16, 1);
        END

        -- Kiểm tra có xác định được branch_id hay không
        IF @BranchId IS NULL
        BEGIN
            RAISERROR (N'Không xác định được chi nhánh của hóa đơn. Kiểm tra lại liên kết court_booking / service_booking.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Lấy loyalty_point_rate từ branch
         * ========================================================= */
        SELECT @LoyaltyRate = loyalty_point_rate
        FROM branch
        WHERE id = @BranchId;

        IF @LoyaltyRate IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy thông tin chi nhánh hoặc loyalty_point_rate không hợp lệ.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 4: Tính toán điểm thưởng cần cộng
         * ========================================================= */

        SELECT @OldBonus = bonus_point
        FROM customer
        WHERE id = @CustomerId;

        IF @OldBonus IS NULL SET @OldBonus = 0;

        -- Tính điểm thưởng dựa trên loyalty_point_rate của branch
        SET @AddedBonus = CAST(@InvoiceAmount * @LoyaltyRate AS INT);

        SET @NewBonus = @OldBonus + ISNULL(@AddedBonus, 0);

        /* =========================================================
         * BƯỚC 5: Cập nhật điểm thưởng cho khách hàng
         * ========================================================= */
        UPDATE customer
        SET bonus_point = @NewBonus
        WHERE id = @CustomerId;

        /* =========================================================
         * BƯỚC 6: Trả kết quả cho phía gọi
         * ========================================================= */
        SELECT
            C.id           AS CustomerId,
            C.full_name    AS CustomerName,
            @InvoiceAmount AS InvoiceAmount,
            @LoyaltyRate   AS LoyaltyRate,
            @OldBonus      AS BonusPointBefore,
            @NewBonus      AS BonusPointAfter
        FROM customer C
        WHERE C.id = @CustomerId;

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

