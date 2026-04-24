/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: TÌM KIẾM LỊCH ĐẶT SÂN THEO NGÀY
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Tìm kiếm lịch đặt sân theo ngày (sp_SearchCourtDailySchedule)
 * Chức năng:
 *   - Nhận thông tin:
 *       + @BookingDate    : Ngày cần xem lịch sân
 *       + @ProvinceCity   : Tỉnh/Thành (lọc theo tên chi nhánh hoặc địa chỉ, ví dụ: N'TP.HCM', N'Hà Nội')
 *       + @BranchName     : Tên cơ sở (ví dụ: N'VietSport TP.HCM')
 *       + @CourtTypeName  : Loại sân (ví dụ: N'Sân Cầu Lông')
 *       + @CourtId        : Id sân cụ thể (ưu tiên nếu truyền vào)
 *   - Trả về danh sách các khung giờ trong ngày từ open_time đến close_time của chi nhánh:
 *       + 'Đã qua'         : Khung giờ đã trôi qua so với thời điểm hiện tại
 *       + 'Đã đặt'         : Có booking + invoice.status = N'Đã thanh toán'
 *       + 'Chờ xác nhận'   : Có booking + invoice.status = N'Chưa thanh toán'
 *       + 'Trống'          : Còn lại (chưa có đặt hoặc không có invoice)
 *
 * Ghi chú:
 *   - Thời lượng mỗi slot lấy từ court_type.rent_duration (phút).
 *   - Nếu @CourtId IS NOT NULL → ưu tiên lấy đúng sân này (và có thể kết hợp các filter khác nếu cần).
 *   - Nếu @CourtId IS NULL → tìm sân theo tỉnh/thành, tên cơ sở và loại sân (chọn MIN(id) nếu có nhiều).
 *   - Nếu không tìm thấy sân phù hợp → Raise Error.
 *
 * Ví dụ sử dụng:
 *   EXEC sp_SearchCourtDailySchedule
 *       @BookingDate = '2024-12-25',
 *       @CourtId     = 1;
 */

CREATE OR ALTER PROCEDURE sp_SearchCourtDailySchedule
(
    @BookingDate    DATE,
    @CourtId        INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRAN;

        /* =========================================================
         * BƯỚC 1: Xác định sân cần tra cứu (@SelectedCourtId)
         * ========================================================= */
        DECLARE @SelectedCourtId INT;

        IF @CourtId IS NOT NULL
        BEGIN
            -- Trường hợp người dùng chỉ định rõ id sân
            SELECT @SelectedCourtId = c.id
            FROM court c
            WHERE c.id = @CourtId
        END
        ELSE
        BEGIN
            RAISERROR (N'Không tìm thấy sân phù hợp với các điều kiện đầu vào.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 2: Lấy rent_duration (phút) của sân và 
         *         open_time, close_time của chi nhánh
         * ========================================================= */
        DECLARE @RentDuration INT;
        DECLARE @OpenTime     TIME;
        DECLARE @CloseTime    TIME;

        SELECT 
            @RentDuration = ct.rent_duration,
            @OpenTime     = B.open_time,
            @CloseTime    = B.close_time
        FROM court c
        JOIN court_type ct ON c.court_type_id = ct.id
        JOIN branch B      ON c.branch_id = B.id
        WHERE c.id = @SelectedCourtId;

        IF @RentDuration IS NULL OR @RentDuration <= 0
        BEGIN
            RAISERROR (N'Không xác định được thời lượng thuê (rent_duration) cho sân.', 16, 1);
        END

        IF @OpenTime IS NULL OR @CloseTime IS NULL
        BEGIN
            RAISERROR (N'Không xác định được giờ mở cửa và đóng cửa của chi nhánh.', 16, 1);
        END

        /* =========================================================
         * BƯỚC 3: Thiết lập khoảng thời gian trong ngày 
         *         từ open_time đến close_time của chi nhánh
         * ========================================================= */
        -- Kết hợp ngày với giờ mở/đóng cửa
        DECLARE @StartOfDay DATETIME = DATEADD(second, DATEDIFF(second, CAST('00:00:00' AS TIME), @OpenTime), CAST(@BookingDate AS DATETIME));
        DECLARE @EndOfDay   DATETIME = DATEADD(second, DATEDIFF(second, CAST('00:00:00' AS TIME), @CloseTime), CAST(@BookingDate AS DATETIME));

        -- Lấy thời điểm hiện tại để xác định slot "Đã qua"
        DECLARE @Now         DATETIME = GETDATE();
        DECLARE @Today       DATE     = CAST(@Now AS DATE);
        DECLARE @CurrentTime TIME     = CAST(@Now AS TIME);

        /* =========================================================
         * BƯỚC 4: Duyệt từng slot và xác định trạng thái
         * ========================================================= */
        DECLARE @Result TABLE
        (
            SlotStart  DATETIME,
            SlotEnd    DATETIME,
            SlotLabel  NVARCHAR(50),
            SlotStatus NVARCHAR(50)
        );

        DECLARE @SlotStart    DATETIME = @StartOfDay;
        DECLARE @SlotEnd      DATETIME;
        DECLARE @Status       NVARCHAR(50);
        DECLARE @InvoiceStatus NVARCHAR(50);
        DECLARE @SlotLabel    NVARCHAR(50);

        WHILE @SlotStart < @EndOfDay
        BEGIN
            SET @SlotEnd = DATEADD(MINUTE, @RentDuration, @SlotStart);

            -- Reset biến mỗi vòng lặp
            SET @Status        = NULL;
            SET @InvoiceStatus = NULL;
            SET @SlotLabel     = NULL;

            -- Label dạng "HH:MM - HH:MM"
            SET @SlotLabel =
                  CONVERT(CHAR(5), CAST(@SlotStart AS TIME), 108)
                + N' - '
                + CONVERT(CHAR(5), CAST(@SlotEnd   AS TIME), 108);

            /* -----------------------------------------------------
             * 4.1. Ưu tiên kiểm tra "Đã qua"
             *     - Nếu ngày nhỏ hơn hôm nay → toàn bộ slot "Đã qua"
             *     - Nếu cùng ngày và giờ hiện tại >= giờ bắt đầu slot → "Đã qua"
             * ----------------------------------------------------- */
            IF @BookingDate < @Today
            BEGIN
                SET @Status = N'Đã qua';
            END
            ELSE IF @BookingDate = @Today 
                 AND CAST(@SlotStart AS TIME) <= @CurrentTime
            BEGIN
                SET @Status = N'Đã qua';
            END
            ELSE
            BEGIN
                /* -------------------------------------------------
                 * 4.2. Chưa "Đã qua" → Kiểm tra booking + invoice
                 *      - Tìm booking_slots khớp với slot này:
                 *          + cùng court_id
                 *          + start_time & end_time trùng
                 *          + cùng ngày @BookingDate
                 *      - Lấy invoice.status tương ứng với court_booking
                 * Chổ này đang phân vân là có nên lấy status của booking_slots không?
                 * ------------------------------------------------- */
                SELECT TOP 1 @InvoiceStatus = I.[status]
                FROM booking_slots BS
                JOIN court_booking CB ON BS.court_booking_id = CB.id
                LEFT JOIN invoice I   ON I.court_booking_id   = CB.id
                WHERE CB.court_id = @SelectedCourtId
                  AND CAST(BS.start_time AS DATE) = @BookingDate
                  AND BS.start_time = @SlotStart
                  AND BS.end_time   = @SlotEnd
                ORDER BY I.created_at DESC;  -- nếu có nhiều invoice thì lấy invoice mới nhất

                IF @InvoiceStatus = N'Đã thanh toán'
                    SET @Status = N'Đã đặt';
                ELSE IF @InvoiceStatus = N'Chưa thanh toán'
                    SET @Status = N'Chờ xác nhận';
                ELSE
                    SET @Status = N'Trống';
            END

            -- Lưu kết quả vào bảng tạm
            INSERT INTO @Result (SlotStart, SlotEnd, SlotLabel, SlotStatus)
            VALUES (@SlotStart, @SlotEnd, @SlotLabel, @Status);

            -- Sang slot tiếp theo
            SET @SlotStart = @SlotEnd;
        END

        /* =========================================================
         * BƯỚC 5: Trả kết quả
         * ========================================================= */
        SELECT 
            SlotLabel   AS [KhungGiờ],
            SlotStatus  AS [TrạngThái],
            SlotStart   AS [StartTime],
            SlotEnd     AS [EndTime]
        FROM @Result
        ORDER BY SlotStart;
        
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        -- Rollback nếu còn transaction
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        DECLARE @ErrMsg      NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrSeverity INT            = ERROR_SEVERITY();

        RAISERROR (@ErrMsg, @ErrSeverity, 1);
    END CATCH
END;
GO

