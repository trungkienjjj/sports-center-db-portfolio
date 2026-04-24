/*
 * =================================================================================
 * STORED PROCEDURES - MODULE: XEM LỊCH SỬ ĐẶT SÂN
 * Người thực hiện: Nguyên
 * =================================================================================
 */

USE SportsCenterDB;
GO

/*
 * Xem lịch sử đặt sân (sp_GetCourtBookingHistoryByCustomer)
 * Chức năng:
 *   - Trả về danh sách các phiếu đặt sân (court_booking) của 1 khách hàng.
 *   - Mỗi dòng tương ứng 1 mã booking, gồm:
 *       + Mã booking     : VS-<id_booking>-<yyyymmdd>
 *       + Sân            : court.name
 *       + Loại sân       : court_type.name
 *       + Khách hàng     : customer.full_name
 *       + Nhân viên      : employee.full_name (hoặc '-' nếu NULL)
 *       + Thời gian      : chuỗi từ booking_slots, ví dụ: "10:00 - 12:00, 13:00 - 15:00, ..."
 *       + TT Thanh toán  : trạng thái thanh toán (Đã thanh toán / Chưa thanh toán / Đã hủy / Chưa có hóa đơn)
 *
 * Input:
 *   @CustomerId : id khách hàng trong bảng [customer]
 *
 * Ví dụ sử dụng:
 *   EXEC sp_GetCourtBookingHistoryByCustomer
 *       @CustomerId = 1;
 */

CREATE OR ALTER PROCEDURE sp_GetCourtBookingHistoryByCustomer
(
    @CustomerId INT
)
AS
BEGIN
    SET NOCOUNT ON;

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
         * BƯỚC 2: Lấy danh sách court_booking kèm court, court_type,
         *          employee, booking_slots, invoice
         * ========================================================= */

        ;WITH BookingBase AS
        (
            SELECT
                CB.id              AS CourtBookingId,
                CB.created_at      AS BookingCreatedAt,
                CB.[status]        AS BookingStatus,
                CRT.[name]         AS CourtName,
                CT.[name]          AS CourtTypeName,
                C.full_name        AS CustomerName,
                E.full_name        AS EmployeeName
            FROM court_booking CB
            JOIN customer C      ON CB.customer_id = C.id
            JOIN court CRT       ON CB.court_id   = CRT.id
            JOIN court_type CT   ON CRT.court_type_id = CT.id
            LEFT JOIN employee E ON CB.employee_id = E.id
            WHERE C.id = @CustomerId
        )
        SELECT
            -- Mã booking: VS-<id_booking>-<yyyymmdd> (ngày lấy theo slot hoặc created_at)
            'VS-' + CAST(BB.CourtBookingId AS VARCHAR(10)) 
                  + '-' 
                  + CONVERT(
                        CHAR(8), 
                        ISNULL(
                            CAST(Slots.MinStartTime AS DATE),
                            CAST(BB.BookingCreatedAt AS DATE)
                        ),
                        112
                    )                                    AS [Mã booking],

            -- Sân: lấy trực tiếp court.name
            BB.CourtName                                  AS [Sân],

            -- Loại sân
            BB.CourtTypeName                              AS [Loại sân],

            -- Khách hàng
            BB.CustomerName                               AS [Khách hàng],

            -- Nhân viên (nếu không có thì hiển thị "-")
            ISNULL(BB.EmployeeName, N'-')                 AS [Nhân viên],

            -- Thời gian: chuỗi các slot, ví dụ: "10:00 - 12:00, 13:00 - 15:00, ..."
            ISNULL(Slots.TimeSlots, N'-')                 AS [Thời gian],

            -- Trạng thái thanh toán: 
            --   - Nếu booking bị hủy (court_booking.status = 'Đã hủy') → 'Đã hủy'
            --   - Nếu có invoice → lấy trực tiếp invoice.status (đã là tiếng Việt)
            --   - Nếu không có invoice → 'Chưa có hóa đơn'
            CASE 
                WHEN BB.BookingStatus = N'Đã hủy' THEN N'Đã hủy'
                WHEN Inv.InvoiceStatus IS NOT NULL THEN Inv.InvoiceStatus
                ELSE N'Chưa có hóa đơn'
            END                                           AS [TT Thanh toán]

        FROM BookingBase BB
        -- Gộp các booking_slots theo booking: nối tất cả slot thành chuỗi
        OUTER APPLY
        (
            SELECT 
                MIN(BS.start_time) AS MinStartTime,  -- Dùng để sắp xếp
                STRING_AGG(
                    CONVERT(CHAR(5), CAST(BS.start_time AS TIME), 108) 
                    + N' - ' 
                    + CONVERT(CHAR(5), CAST(BS.end_time AS TIME), 108),
                    N', '
                ) WITHIN GROUP (ORDER BY BS.start_time) AS TimeSlots
            FROM booking_slots BS
            WHERE BS.court_booking_id = BB.CourtBookingId
        ) AS Slots

        -- Lấy 1 invoice gần nhất cho mỗi booking (nếu có)
        OUTER APPLY
        (
            SELECT TOP 1
                I.[status] AS InvoiceStatus
            FROM invoice I
            WHERE I.court_booking_id = BB.CourtBookingId
            ORDER BY I.created_at DESC, I.id DESC
        ) AS Inv

        -- Sắp xếp: mới nhất trước (theo thời gian slot, rồi tới id)
        ORDER BY 
            ISNULL(Slots.MinStartTime, BB.BookingCreatedAt) DESC,
            BB.CourtBookingId DESC;

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

