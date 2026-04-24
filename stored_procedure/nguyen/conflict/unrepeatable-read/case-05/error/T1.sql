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

        -- 2.1. Nếu có slot đã sử dụng → không cho hủy
        IF EXISTS (
            SELECT 1
            FROM booking_slots
            WHERE court_booking_id = @CourtBookingId
              AND [status] = N'Đã sử dụng'
        )
        BEGIN
            RAISERROR (N'Không thể hủy: Sân đã được sử dụng (slot status = N''Đã sử dụng'').', 16, 1);
        END

        -- 2.2. Lấy giờ bắt đầu sớm nhất của booking
        SELECT
            @FirstSlotStart = MIN(start_time)
        FROM booking_slots
        WHERE court_booking_id = @CourtBookingId;

        IF @FirstSlotStart IS NULL
        BEGIN
            RAISERROR (N'Phiếu đặt sân này chưa có booking slots, không thể áp dụng chính sách hủy.', 16, 1);
        END

        -- 2.3. Nếu đã qua giờ bắt đầu slot đầu tiên → không cho hủy (No show xử lý luồng khác)
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

        PRINT 'Loyalty rate branch: ' + CAST(@LoyaltyRateBranch AS NVARCHAR(10));
        PRINT 'Cancel before 24 percent: ' + CAST(@CancelBefore24Percent AS NVARCHAR(10));
        PRINT 'Cancel within 24 percent: ' + CAST(@CancelWithin24Percent AS NVARCHAR(10));
        
        PRINT 'Waiting for 20 seconds...';
        WAITFOR DELAY '00:00:20';
        PRINT 'Done waiting';
        
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

        -- Tính tổng số tiền hoàn từ các dịch vụ
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

-- ====================================================================
-- Demo Unrepeatable Read (CourtBookingId = 1)
-- T1 - Lễ tân:
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  BEGIN TRAN;
  EXEC sp_CancelCourtBooking
      @CourtBookingId = 4,
      @Method = N'Tiền mặt',
      @Type = N'CourtCancel',
      @Reason = N'Khách hủy';
  COMMIT;
  -- Proc sẽ chờ 20s sau khi đọc cấu hình phạt.

-- Kết quả mong đợi: T1 tính phạt theo cấu hình cũ (ví dụ 50%) mặc dù T2 đã đổi lên 70% giữa chừng → minh họa unrepeatable read/stale config.

-- ====================================================================
-- Script tạo nhanh 1 phiếu đặt sân trong <24h (bypass rule đặt trước 2h)
-- Điều chỉnh các ID cho phù hợp dữ liệu thật.
-- CourtBookingId mới dùng cho test unrepeatable read/hủy sân.
-- ====================================================================

USE SportsCenterDB;
GO

-- Script insert court_booking với slot cách hiện tại 5 giờ
-- Dùng để test sp_CancelCourtBooking

DECLARE 
    @CourtId INT,
    @BasePrice DECIMAL(10, 2),
    @RentDuration INT,
    @SlotStartTime DATETIME,
    @SlotEndTime DATETIME,
    @BookingDate DATE,
    @CourtBookingId INT,
    @InvoiceId INT;

-- 1. Lấy court_id đầu tiên thuộc branch_id = 1 (có status = N'Sẵn sàng')
SELECT TOP 1
    @CourtId = C.id,
    @BasePrice = C.base_hourly_price,
    @RentDuration = CT.rent_duration
FROM court C
JOIN court_type CT ON C.court_type_id = CT.id
WHERE C.branch_id = 1
  AND C.[status] = N'Sẵn sàng'
ORDER BY C.id;

-- Kiểm tra có court hợp lệ không
IF @CourtId IS NULL
BEGIN
    RAISERROR(N'Không tìm thấy sân hợp lệ thuộc branch_id = 1', 16, 1);
    RETURN;
END

-- 2. Tính toán thời gian slot (cách hiện tại 5 giờ)
SET @SlotStartTime = DATEADD(HOUR, 5, GETDATE());
SET @SlotEndTime = DATEADD(MINUTE, @RentDuration, @SlotStartTime);
SET @BookingDate = CAST(@SlotStartTime AS DATE);

PRINT N'Thông tin booking:';
PRINT N'Court ID: ' + CAST(@CourtId AS NVARCHAR(10));
PRINT N'Base Price: ' + CAST(@BasePrice AS NVARCHAR(20));
PRINT N'Slot Start: ' + CONVERT(NVARCHAR(20), @SlotStartTime, 120);
PRINT N'Slot End: ' + CONVERT(NVARCHAR(20), @SlotEndTime, 120);
PRINT N'Booking Date: ' + CONVERT(NVARCHAR(20), @BookingDate, 120);

-- 3. Insert court_booking
INSERT INTO court_booking (
    [type],
    [status],
    [by_month],
    [booked_base_price],
    [holiday_charge],
    [weekend_charge],
    [customer_id],
    [employee_id],
    [court_id],
    [booking_date],
    [created_at]
)
VALUES (
    N'Online',                    -- type
    N'Đã thanh toán',             -- status
    0,                            -- by_month
    @BasePrice,                   -- booked_base_price
    0.00,                         -- holiday_charge
    0.00,                         -- weekend_charge
    1,                            -- customer_id
    NULL,                         -- employee_id (Online nên NULL)
    @CourtId,                     -- court_id
    @BookingDate,                 -- booking_date
    GETDATE()                     -- created_at
);

SET @CourtBookingId = SCOPE_IDENTITY();
PRINT N'Court Booking ID: ' + CAST(@CourtBookingId AS NVARCHAR(10));

-- 4. Insert booking_slots
INSERT INTO booking_slots (
    [start_time],
    [end_time],
    [status],
    [night_charge],
    [court_booking_id]
)
VALUES (
    @SlotStartTime,               -- start_time
    @SlotEndTime,                 -- end_time
    N'Đã đặt',                    -- status
    0.00,                         -- night_charge
    @CourtBookingId               -- court_booking_id
);

PRINT N'Booking slot đã được tạo';

-- 5. Insert invoice (đã thanh toán)
INSERT INTO invoice (
    [total_amount],
    [payment_method],
    [status],
    [employee_id],
    [court_booking_id],
    [service_booking_id],
    [created_at]
)
VALUES (
    @BasePrice,                   -- total_amount (giá gốc, chưa trừ discount)
    N'Tiền mặt',                  -- payment_method
    N'Đã thanh toán',             -- status
    NULL,                         -- employee_id (có thể NULL)
    @CourtBookingId,              -- court_booking_id
    NULL,                         -- service_booking_id (phải NULL vì đây là invoice cho sân)
    GETDATE()                     -- created_at
);

SET @InvoiceId = SCOPE_IDENTITY();
PRINT N'Invoice ID: ' + CAST(@InvoiceId AS NVARCHAR(10));
PRINT N'Total Amount: ' + CAST(@BasePrice AS NVARCHAR(20));

-- 6. Hiển thị thông tin tổng hợp
SELECT 
    @CourtBookingId AS CourtBookingId,
    @InvoiceId AS InvoiceId,
    @CourtId AS CourtId,
    @SlotStartTime AS SlotStartTime,
    @SlotEndTime AS SlotEndTime,
    @BasePrice AS TotalAmount,
    N'Đã thanh toán' AS PaymentStatus;

PRINT N'========================================';
PRINT N'Hoàn tất tạo court_booking và invoice';
PRINT N'CourtBookingId: ' + CAST(@CourtBookingId AS NVARCHAR(10));
PRINT N'Có thể dùng ID này để test sp_CancelCourtBooking';
PRINT N'========================================';
GO
