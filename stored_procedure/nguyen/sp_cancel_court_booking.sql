/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: HỦY SÂN
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Hủy sân (sp_CancelCourtBooking)
 * Chức năng:
 *   - Hủy một phiếu đặt sân (court_booking) và toàn bộ dịch vụ đi kèm.
 *   - Áp dụng chính sách phí hủy sân theo chi nhánh:
 *       + cancel_fee_before_24h_percent: Hủy trước 24h.
 *       + cancel_fee_within_24h_percent : Hủy trong vòng 24h trước giờ chơi.
 *       + No-show: KHÔNG xử lý trong SP này (vì người dùng không thao tác hủy khi không đến).
 *   - Không cho hủy nếu:
 *       + Đã có booking_slots.status = N'Đã sử dụng' → coi như đã chơi.
 *       + Hoặc đã qua giờ bắt đầu slot đầu tiên.
 *   - Tính tiền phạt sân dựa trên invoice.total_amount (tiền khách thực trả).
 *   - Hủy các dịch vụ đi kèm (service_booking) bằng cách gọi sp_CancelServiceBooking.
 *   - Trừ lại bonus point của khách hàng tương ứng với tổng số tiền được hoàn
 *     (cả sân + dịch vụ), dựa trên loyalty_point_rate của chi nhánh.
 *
 * Input:
 *   @CourtBookingId  : Mã đặt sân (court_booking.id)
 *   @Method          : Phương thức hoàn tiền (Tiền mặt / Chuyển khoản / Thẻ / Ví điện tử)
 *   @Type            : Loại hoàn tiền (ví dụ: 'CourtCancel', 'ServiceCancel', ...)
 *   @Reason          : Lý do hoàn tiền
 *
 * Quy ước business:
 *   1. Nếu đã có slot status = N'Đã sử dụng' → KHÔNG cho hủy (đã chơi sân).
 *   2. No-show không xử lý ở đây (không tự hủy).
 *      → Nếu GETDATE() >= start_time slot đầu tiên → KHÔNG cho hủy.
 *   3. Tiền phạt sân tính trên invoice.total_amount (tiền khách thực trả).
 *   4. Hủy là hủy cả court_booking (mọi slot thuộc booking đều bị hủy),
 *      không cho hủy riêng từng slot.
 *   5. Logic hủy dịch vụ sử dụng sp_CancelServiceBooking để đảm bảo tính nhất quán.
 *   6. Nếu booking chưa thanh toán (invoice.status <> N'Đã thanh toán'):
 *        → cho hủy free, set status = N'Đã hủy', KHÔNG tạo refund, KHÔNG trừ/hoàn điểm.
 *   7. Khi hoàn tiền, trừ lại bonus point tương ứng với số tiền được hoàn (sân + dịch vụ).
 *   8. Thời điểm hủy = GETDATE() trên DB server.
 *
 * Ví dụ sử dụng:
 *   EXEC sp_CancelCourtBooking
 *       @CourtBookingId = 5,
 *       @Method         = N'Chuyển khoản',
 *       @Type           = N'CourtCancel',
 *       @Reason         = N'Khách hàng thay đổi kế hoạch';
 */

CREATE OR ALTER PROCEDURE sp_CancelCourtBooking
(
    @CourtBookingId INT,
    @Method         NVARCHAR(50),
    @Type           NVARCHAR(50),
    @Reason         NVARCHAR(500)
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        -- Thông tin booking
        @BookingStatus        NVARCHAR(50),
        @CustomerId           INT,
        @CourtId              INT,

        -- Thông tin thời gian
        @Now                  DATETIME,
        @FirstSlotStart       DATETIME,

        -- Thông tin chi nhánh & loyalty
        @BranchId             INT,
        @LoyaltyRateBranch    DECIMAL(5, 2),
        @CancelBefore24Percent DECIMAL(5, 2),
        @CancelWithin24Percent DECIMAL(5, 2),

        -- Hóa đơn sân
        @InvoiceCourtId       INT,
        @InvoiceCourtStatus   NVARCHAR(50),
        @InvoiceCourtTotal    DECIMAL(10, 2),

        -- Phí & hoàn tiền sân
        @PenaltyPercent       DECIMAL(5, 2),
        @PenaltyAmount        DECIMAL(10, 2),
        @RefundCourtAmount    DECIMAL(10, 2),

        -- Bonus point cho khách
        @CustomerOldBonus     INT,
        @CustomerNewBonus     INT,
        @BonusSubtractCourt   INT,

        -- Biến dùng cho vòng lặp hủy dịch vụ
        @ServiceBookingId     INT,
        @TotalRefundService    DECIMAL(10, 2),
        @RefundServiceAmount   DECIMAL(10, 2);

    BEGIN TRY
        BEGIN TRAN;

        SET @Now = GETDATE();
        SET @TotalRefundService = 0;

        /* =========================================================
         * BƯỚC 1: Kiểm tra phiếu đặt sân tồn tại & trạng thái
         * ========================================================= */

        SELECT
            @BookingStatus = CB.[status],
            @CustomerId    = CB.customer_id,
            @CourtId       = CB.court_id
        FROM court_booking CB
        WHERE CB.id = @CourtBookingId;

        IF @BookingStatus IS NULL
        BEGIN
            RAISERROR (N'Không tìm thấy phiếu đặt sân với mã đã cung cấp.', 16, 1);
        END

        IF @BookingStatus = N'Đã hủy'
        BEGIN
            RAISERROR (N'Phiếu đặt sân này đã được hủy trước đó.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Kiểm tra slot đã sử dụng và thời gian hủy
         * ========================================================= */

        -- 3.1. Nếu có slot đã sử dụng → không cho hủy
        IF EXISTS (
            SELECT 1
            FROM booking_slots
            WHERE court_booking_id = @CourtBookingId
              AND [status] = N'Đã sử dụng'
        )
        BEGIN
            RAISERROR (N'Không thể hủy: Sân đã được sử dụng (slot status = N''Đã sử dụng'').', 16, 1);
        END

        -- 3.2. Lấy giờ bắt đầu sớm nhất của booking
        SELECT
            @FirstSlotStart = MIN(start_time)
        FROM booking_slots
        WHERE court_booking_id = @CourtBookingId;

        IF @FirstSlotStart IS NULL
        BEGIN
            RAISERROR (N'Phiếu đặt sân này chưa có booking slots, không thể áp dụng chính sách hủy.', 16, 1);
        END

        -- 3.3. Nếu đã qua giờ bắt đầu slot đầu tiên → không cho hủy (No show xử lý luồng khác)
        IF @Now >= @FirstSlotStart
        BEGIN
            RAISERROR (N'Đã qua giờ bắt đầu, không thể hủy sân (trường hợp No-show không xử lý trong SP này).', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Lấy thông tin chi nhánh & loyalty của sân
         * ========================================================= */

        SELECT
            @BranchId = CRT.branch_id
        FROM court CRT
        WHERE CRT.id = @CourtId;

        SELECT
            @LoyaltyRateBranch      = B.loyalty_point_rate,
            @CancelBefore24Percent  = B.cancel_fee_before_24h_percent,
            @CancelWithin24Percent  = B.cancel_fee_within_24h_percent
        FROM branch B
        WHERE B.id = @BranchId;

        IF @LoyaltyRateBranch IS NULL SET @LoyaltyRateBranch = 0;
        IF @CancelBefore24Percent IS NULL SET @CancelBefore24Percent = 0;
        IF @CancelWithin24Percent IS NULL SET @CancelWithin24Percent = 0;

        /* =========================================================
         * BƯỚC 4: Lấy hóa đơn sân (invoice.court_booking_id)
         *         và tính phí/hoàn tiền nếu đã Paid
         * ========================================================= */

        SELECT TOP 1
            @InvoiceCourtId     = I.id,
            @InvoiceCourtStatus = I.[status],
            @InvoiceCourtTotal  = I.total_amount
        FROM invoice I
        WHERE I.court_booking_id = @CourtBookingId
        ORDER BY I.created_at DESC, I.id DESC;

        SET @RefundCourtAmount = 0;
        SET @PenaltyPercent    = 0;
        SET @PenaltyAmount     = 0;

        IF @InvoiceCourtId IS NOT NULL AND @InvoiceCourtStatus = N'Đã thanh toán'
        BEGIN
            -- 5.1. Chọn mức phần trăm phạt theo mốc 24h
            IF @Now < DATEADD(HOUR, -24, @FirstSlotStart)
            BEGIN
                -- Hủy trước 24h
                SET @PenaltyPercent = @CancelBefore24Percent;
            END
            ELSE
            BEGIN
                -- Hủy trong vòng 24h trước giờ bắt đầu
                SET @PenaltyPercent = @CancelWithin24Percent;
            END

            -- 5.2. Tính số tiền phạt & số tiền hoàn (theo invoice.total_amount)
            SET @PenaltyAmount = ISNULL(@InvoiceCourtTotal, 0) * ISNULL(@PenaltyPercent, 0);
            IF @PenaltyAmount < 0 SET @PenaltyAmount = 0;
            IF @PenaltyAmount > @InvoiceCourtTotal SET @PenaltyAmount = @InvoiceCourtTotal;

            SET @RefundCourtAmount = ISNULL(@InvoiceCourtTotal, 0) - @PenaltyAmount;
            IF @RefundCourtAmount < 0 SET @RefundCourtAmount = 0;

            -- 5.3. Trừ lại bonus point theo số tiền được hoàn (sân)
            SELECT
                @CustomerOldBonus = bonus_point
            FROM customer
            WHERE id = @CustomerId;

            IF @CustomerOldBonus IS NULL SET @CustomerOldBonus = 0;

            SET @BonusSubtractCourt = CAST(@RefundCourtAmount * @LoyaltyRateBranch AS INT);
            IF @BonusSubtractCourt < 0 SET @BonusSubtractCourt = 0;

            SET @CustomerNewBonus =
                CASE
                    WHEN @CustomerOldBonus < @BonusSubtractCourt THEN 0
                    ELSE @CustomerOldBonus - @BonusSubtractCourt
                END;

            UPDATE customer
            SET bonus_point = @CustomerNewBonus
            WHERE id = @CustomerId;
        END
        -- ELSE: invoice không Đã thanh toán → cho hủy free, không refund, không trừ điểm.

        /* =========================================================
         * BƯỚC 5: Hủy toàn bộ dịch vụ đi kèm (service_booking)
         *   - Sử dụng sp_CancelServiceBooking để đảm bảo tính nhất quán
         *   - Tổng hợp số tiền hoàn từ các dịch vụ để tính tổng
         * ========================================================= */

        DECLARE curServiceBooking CURSOR LOCAL FAST_FORWARD FOR
            SELECT id
            FROM service_booking
            WHERE court_booking_id = @CourtBookingId
              AND [status] <> N'Đã hủy';  -- Chỉ hủy các dịch vụ chưa hủy

        OPEN curServiceBooking;
        FETCH NEXT FROM curServiceBooking INTO @ServiceBookingId;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Gọi sp_CancelServiceBooking để hủy dịch vụ
            -- SP này sẽ tự xử lý: hoàn tiền, cộng lại tồn kho, trừ bonus point, tạo refund_info
            EXEC sp_CancelServiceBooking
                @CourtBookingId   = @CourtBookingId,
                @ServiceBookingId = @ServiceBookingId,
                @Method           = @Method,
                @Type             = @Type,
                @Reason           = @Reason;

            FETCH NEXT FROM curServiceBooking INTO @ServiceBookingId;
        END

        CLOSE curServiceBooking;
        DEALLOCATE curServiceBooking;

        -- Tính tổng số tiền hoàn từ các dịch vụ (từ refund_info đã được tạo bởi sp_CancelServiceBooking)
        SELECT
            @TotalRefundService = ISNULL(SUM(RI.amount), 0)
        FROM refund_info RI
        JOIN invoice I ON RI.invoice_id = I.id
        JOIN service_booking SB ON I.service_booking_id = SB.id
        WHERE SB.court_booking_id = @CourtBookingId
          AND RI.[status] = N'Chờ xử lý';

        /* =========================================================
         * BƯỚC 6: Ghi refund_info cho hóa đơn sân (nếu có hoàn tiền)
         * ========================================================= */

        IF @InvoiceCourtId IS NOT NULL
           AND @InvoiceCourtStatus = N'Đã thanh toán'
           AND @RefundCourtAmount > 0
        BEGIN
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
                @RefundCourtAmount,
                @Reason,
                @Type,
                @Method,
                N'Chờ xử lý',
                @InvoiceCourtId
            );
        END
        -- Nếu invoice không Đã thanh toán hoặc RefundCourtAmount = 0 → không tạo refund cho sân.

        /* =========================================================
         * BƯỚC 7: Cập nhật trạng thái booking_slots & court_booking
         * ========================================================= */

        UPDATE booking_slots
        SET [status] = N'Đã hủy'
        WHERE court_booking_id = @CourtBookingId;

        UPDATE court_booking
        SET [status] = N'Đã hủy'
        WHERE id = @CourtBookingId;

        /* =========================================================
         * BƯỚC 8: Trả kết quả tổng quan cho phía gọi
         * ========================================================= */

        SELECT
            @CourtBookingId             AS CourtBookingId,
            @InvoiceCourtId             AS CourtInvoiceId,
            @RefundCourtAmount          AS CourtRefundAmount,
            @TotalRefundService         AS ServiceRefundAmount,
            (@RefundCourtAmount + @TotalRefundService) AS TotalRefundAmount;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE
            @ErrMsg   NVARCHAR(4000) = ERROR_MESSAGE(),
            @ErrSev   INT            = ERROR_SEVERITY(),
            @ErrState INT            = ERROR_STATE();

        RAISERROR (@ErrMsg, @ErrSev, @ErrState);
    END CATCH
END;
GO

