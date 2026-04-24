/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: HỦY DỊCH VỤ
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Hủy dịch vụ (sp_CancelServiceBooking)
 * Chức năng:
 *   1. Kiểm tra service_booking tồn tại và thuộc đúng court_booking.
 *   2. Lấy invoice dịch vụ (invoice.service_booking_id) và đảm bảo status = 'Paid'.
 *   3. Xác định các service_booking_item CHƯA dùng (start_time > NOW):
 *        - Tính tổng tiền hoàn = SUM(quantity * unit_price) của nhóm này.
 *        - Tính tổng quantity theo từng branch_service_id để cộng lại tồn kho.
 *   4. Cộng lại tồn kho:
 *        - branch_service.current_stock += total_qty_unused (theo từng service).
 *   5. Trừ bonus_point:
 *        - Xác định khách hàng từ court_booking.
 *        - Xác định chi nhánh (branch) từ branch_service của service_booking_item.
 *        - Lấy loyalty_point_rate của branch.
 *        - BonusToSubtract = CAST(RefundAmount * loyalty_point_rate AS INT).
 *        - Cập nhật customer.bonus_point = MAX(0, old_bonus - BonusToSubtract).
 *   6. Cập nhật service_booking.status = N'Đã hủy'.
 *   7. Tạo bản ghi refund_info:
 *        - amount  = RefundAmount
 *        - method  = @Method (được kiểm tra bởi trigger)
 *        - type    = @Type
 *        - reason  = @Reason
 *        - status  = N'Chờ xử lý' nếu amount > 0, ngược lại N'Đã xử lý'
 *   8. Trả về dòng refund_info vừa tạo.
 *
 * Input:
 *   @CourtBookingId     : Mã đặt sân (court_booking_id)
 *   @ServiceBookingId   : Mã đặt dịch vụ (service_booking_id)
 *   @Method             : Phương thức hoàn tiền (Tiền mặt / Chuyển khoản / Thẻ / Ví điện tử)
 *   @Type               : Loại hoàn tiền (ví dụ: 'ServiceCancel', 'CourtCancel', ...)
 *   @Reason             : Lý do hoàn tiền
 *
 * Ví dụ sử dụng:
 *   EXEC sp_CancelServiceBooking
 *       @CourtBookingId   = 5,
 *       @ServiceBookingId = 10,
 *       @Method           = N'Tiền mặt',
 *       @Type             = N'ServiceCancel',
 *       @Reason           = N'Khách hàng không cần dịch vụ này nữa';
 */

CREATE OR ALTER PROCEDURE sp_CancelServiceBooking
(
    @CourtBookingId   INT,
    @ServiceBookingId INT,
    @Method           NVARCHAR(50),
    @Type             NVARCHAR(50),
    @Reason           NVARCHAR(500)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @Now                DATETIME,
        @CurrentStatus      NVARCHAR(50),
        @InvoiceId          INT,
        @InvoiceStatus      NVARCHAR(50),
        @RefundAmount       DECIMAL(10, 2),
        @RefundStatus       NVARCHAR(50),
        @RefundId           INT,

        -- Biến phục vụ trừ bonus
        @CustomerIdForBonus INT,
        @BranchIdForBonus   INT,
        @LoyaltyRate        DECIMAL(5, 2),
        @OldBonus           INT,
        @BonusToSubtract    INT,
        @NewBonus           INT;

    -- Table variable để lưu các dịch vụ chưa sử dụng
    DECLARE @UnusedItems TABLE
    (
        branch_service_id INT,
        TotalQty          INT,
        TotalAmount       DECIMAL(10, 2)
    );

    BEGIN TRY
        BEGIN TRAN;

        /* =========================================================
         * BƯỚC 1: Kiểm tra service_booking có tồn tại
         *         và thuộc đúng court_booking hay không
         * ========================================================= */

        SELECT 
            @CurrentStatus = [status]
        FROM service_booking
        WHERE id = @ServiceBookingId
          AND court_booking_id = @CourtBookingId;

        IF @CurrentStatus IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy phiếu đặt dịch vụ tương ứng với mã đặt sân và mã dịch vụ đã cung cấp.', 16, 1);
        END

        IF @CurrentStatus = N'Đã hủy'
        BEGIN
            RAISERROR (N'Phiếu đặt dịch vụ này đã được hủy trước đó.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Lấy hóa đơn dịch vụ tương ứng (invoice.service_booking_id)
         * ========================================================= */

        SELECT TOP 1
            @InvoiceId     = I.id,
            @InvoiceStatus = I.[status]
        FROM invoice I
        WHERE I.service_booking_id = @ServiceBookingId
        ORDER BY I.created_at DESC, I.id DESC;

        IF @InvoiceId IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy hóa đơn dịch vụ tương ứng để hoàn tiền.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Xác định các dịch vụ CHƯA sử dụng và
         *         tính tổng tiền hoàn + tổng quantity để cộng lại tồn kho
         * ========================================================= */

        SET @Now = GETDATE();

        -- Lưu các dịch vụ chưa sử dụng vào table variable
        INSERT INTO @UnusedItems (branch_service_id, TotalQty, TotalAmount)
        SELECT
            SBI.branch_service_id,
            SUM(SBI.quantity)                          AS TotalQty,
            SUM(SBI.quantity * BS.unit_price)          AS TotalAmount
        FROM service_booking_item SBI
        JOIN branch_service BS
            ON SBI.branch_service_id = BS.id
        WHERE SBI.service_booking_id = @ServiceBookingId
          AND SBI.start_time > @Now    
        GROUP BY SBI.branch_service_id;

        -- Tính tiền hoàn
        SELECT 
            @RefundAmount = ISNULL(SUM(TotalAmount), 0.0)
        FROM @UnusedItems;

        /* =========================================================
         * BƯỚC 4: Cộng lại tồn kho dịch vụ cho các item CHƯA sử dụng
         *   - Nếu không có item nào chưa dùng → không đổi tồn kho
         * ========================================================= */

        UPDATE BS
        SET BS.current_stock = BS.current_stock + UI.TotalQty
        FROM branch_service BS
        JOIN @UnusedItems UI
            ON BS.id = UI.branch_service_id;

        /* =========================================================
         * BƯỚC 5: Trừ lại bonus_point đã cộng cho khách hàng
         *   - Dựa trên số tiền được hoàn @RefundAmount
         *   - Sử dụng loyalty_point_rate của chi nhánh (branch)
         *     giống logic TG_R1405_BonusPoint.
         * ========================================================= */

        -- 5.1. Xác định khách hàng của phiếu đặt sân (court_booking)
        SELECT 
            @CustomerIdForBonus = CB.customer_id
        FROM court_booking CB
        JOIN service_booking SB
            ON SB.court_booking_id = CB.id
        WHERE SB.id = @ServiceBookingId;

        -- 5.2. Xác định chi nhánh (branch) của dịch vụ
        --      (giả định mọi dịch vụ trong 1 service_booking cùng 1 chi nhánh)
        SELECT TOP 1
            @BranchIdForBonus = BS.branch_id
        FROM service_booking_item SBI
        JOIN branch_service BS
            ON SBI.branch_service_id = BS.id
        WHERE SBI.service_booking_id = @ServiceBookingId
        ORDER BY SBI.id;

        -- 5.3. Lấy loyalty_point_rate của chi nhánh
        SELECT 
            @LoyaltyRate = loyalty_point_rate
        FROM branch
        WHERE id = @BranchIdForBonus;

        IF @LoyaltyRate IS NULL
            SET @LoyaltyRate = 0;

        -- 5.4. Lấy bonus_point hiện tại của khách
        SELECT 
            @OldBonus = bonus_point
        FROM customer
        WHERE id = @CustomerIdForBonus;

        IF @OldBonus IS NULL
            SET @OldBonus = 0;

        -- 5.5. Tính số điểm cần trừ, dựa trên số tiền được hoàn
        --      BonusToSubtract = CAST(RefundAmount * loyalty_point_rate AS INT)
        SET @BonusToSubtract = CAST(@RefundAmount * @LoyaltyRate AS INT);
        IF @BonusToSubtract < 0 SET @BonusToSubtract = 0;

        -- 5.6. Tính bonus mới, không để âm
        SET @NewBonus = CASE 
                            WHEN @OldBonus < @BonusToSubtract 
                                THEN 0 
                            ELSE @OldBonus - @BonusToSubtract 
                        END;

        -- 5.7. Cập nhật bonus_point cho khách hàng (nếu xác định được khách)
        IF @CustomerIdForBonus IS NOT NULL
        BEGIN
            UPDATE customer
            SET bonus_point = @NewBonus
            WHERE id = @CustomerIdForBonus;
        END

        /* =========================================================
         * BƯỚC 6: Cập nhật trạng thái phiếu đặt dịch vụ → N'Đã hủy'
         * ========================================================= */

        UPDATE service_booking
        SET [status] = N'Đã hủy'
        WHERE id = @ServiceBookingId;

        /* =========================================================
         * BƯỚC 7: Ghi nhận thông tin hoàn tiền vào refund_info
         *   - Nếu @RefundAmount > 0  → status = N'Chờ xử lý'
         *   - Nếu @RefundAmount = 0  → status = N'Đã xử lý'
         * ========================================================= */

        SET @RefundStatus = CASE 
                                WHEN @RefundAmount > 0 THEN N'Chờ xử lý'
                                ELSE N'Đã xử lý'
                            END;

        INSERT INTO refund_info
        (
            amount,
            reason,
            [type],
            [method],
            [status],
            invoice_id
        )
        VALUES
        (
            @RefundAmount,
            @Reason,
            @Type,
            @Method,
            @RefundStatus,
            @InvoiceId
        );

        SET @RefundId = SCOPE_IDENTITY();

        /* =========================================================
         * BƯỚC 8: Trả kết quả cho phía gọi
         *   (tập trung vào thông tin hoàn tiền như yêu cầu)
         * ========================================================= */

        SELECT
            R.id          AS RefundId,
            R.amount      AS RefundAmount,
            R.reason      AS Reason,
            R.[type]      AS RefundType,
            R.[method]    AS RefundMethod,
            R.[status]    AS RefundStatus,
            R.invoice_id  AS InvoiceId,
            R.created_at  AS CreatedAt
        FROM refund_info R
        WHERE R.id = @RefundId;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE
            @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrSev INT            = ERROR_SEVERITY(),
            @ErrState INT          = ERROR_STATE();

        RAISERROR (@ErrMsg, @ErrSev, @ErrState);
    END CATCH
END;
GO

