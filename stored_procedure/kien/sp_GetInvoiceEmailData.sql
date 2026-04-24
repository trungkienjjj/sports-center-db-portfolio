USE SportsCenterDB;
GO
/* * 4.1. Lấy dữ liệu gửi mail hóa đơn (sp_GetInvoiceEmailData) */
CREATE OR ALTER PROCEDURE sp_GetInvoiceEmailData
    @InvoiceID INT
AS
BEGIN
    SET NOCOUNT ON;
    -- Header
    SELECT i.id AS InvoiceNumber, i.created_at, i.total_amount, c.full_name, c.email
    FROM invoice i
    LEFT JOIN court_booking cb ON i.court_booking_id = cb.id
    LEFT JOIN customer c ON cb.customer_id = c.id
    WHERE i.id = @InvoiceID;

    -- Court Details
    SELECT ct.name AS CourtType, c.status, bs.start_time, bs.end_time
    FROM invoice i
    JOIN court_booking cb ON i.court_booking_id = cb.id
    JOIN court c ON cb.court_id = c.id
    JOIN court_type ct ON c.court_type_id = ct.id
    JOIN booking_slots bs ON cb.id = bs.court_booking_id
    WHERE i.id = @InvoiceID;

    -- Service Details
    SELECT s.name AS ServiceName, sbi.quantity, bs.unit_price, (sbi.quantity * bs.unit_price) AS TotalPrice
    FROM invoice i
    JOIN service_booking sb ON i.service_booking_id = sb.id
    JOIN service_booking_item sbi ON sb.id = sbi.service_booking_id
    JOIN branch_service bs ON sbi.branch_service_id = bs.id
    JOIN service s ON bs.service_id = s.id
    WHERE i.id = @InvoiceID;
END;
GO