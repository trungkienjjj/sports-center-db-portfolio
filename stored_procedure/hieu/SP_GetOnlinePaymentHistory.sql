USE SportsCenterDB;
GO

-- =============================================
-- 9. SP_GetOnlinePaymentHistory
-- Mô tả: Xem lịch sử thanh toán online
-- Params: FromDate, ToDate, Status, EmployeeId (Cashier), InvoiceId, CustomerName
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetOnlinePaymentHistory
    @FromDate DATE = NULL,
    @ToDate DATE = NULL,
    @Status NVARCHAR(50) = NULL, 
    @EmployeeId INT = NULL, -- Thu ngân (Cashier)
    @InvoiceId INT = NULL, -- Mã hóa đơn để tìm kiếm
    @CustomerName NVARCHAR(255) = NULL -- Tên khách hàng để tìm kiếm
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Mặc định lấy tháng hiện tại nếu không truyền ngày
    IF @FromDate IS NULL
        SET @FromDate = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);
    IF @ToDate IS NULL
        SET @ToDate = EOMONTH(GETDATE());
    
    -- Result Set 1: Thống kê tổng quan
    SELECT 
        COUNT(i.id) AS TotalInvoices, -- Tổng hóa đơn
        SUM(CASE WHEN i.[status] = N'Đã thanh toán' THEN 1 ELSE 0 END) AS PaidInvoices, -- Tổng đã thanh toán
        SUM(CASE WHEN i.[status] = N'Chưa thanh toán' THEN 1 ELSE 0 END) AS UnpaidInvoices, -- Tổng chưa thanh toán
        SUM(CASE WHEN cb.[status] = N'Đã hủy' OR sb.[status] = N'Đã hủy' THEN 1 ELSE 0 END) AS CancelledInvoices -- Tổng đã hủy
    FROM invoice i
    LEFT JOIN court_booking cb ON i.court_booking_id = cb.id
    LEFT JOIN service_booking sb ON i.service_booking_id = sb.id
    LEFT JOIN customer cust ON cb.customer_id = cust.id
    WHERE CAST(i.created_at AS DATE) BETWEEN @FromDate AND @ToDate
        AND (@Status IS NULL OR i.[status] = @Status) -- Lọc theo trạng thái
        AND (@EmployeeId IS NULL OR i.employee_id = @EmployeeId) -- Lọc theo thu ngân
        AND (@InvoiceId IS NULL OR i.id = @InvoiceId) -- Lọc theo mã hóa đơn
        AND (@CustomerName IS NULL OR cust.full_name LIKE N'%' + @CustomerName + N'%'); -- Lọc theo tên khách hàng
    
    -- Result Set 2: Chi tiết danh sách hóa đơn thanh toán online
    SELECT 
        i.id AS InvoiceId, -- Mã hóa đơn
        cb.id AS BookingCode, -- Mã đặt sân (trả về trực tiếp)
        cust.full_name AS CustomerName, -- Khách hàng
        i.created_at AS CreatedAt, -- Ngày tạo
        i.payment_method AS PaymentMethod, -- Hình thức thanh toán
        emp.full_name AS CashierName, -- Thu ngân
        c.[name] AS CourtName, -- Tên sân đã đặt (VD: "Sân Tennis 1")
        b.[name] AS BranchName, -- Cơ sở
        i.total_amount AS TotalAmount, -- Tổng tiền
        i.[status] AS InvoiceStatus -- Trạng thái hóa đơn
    FROM invoice i
    LEFT JOIN court_booking cb ON i.court_booking_id = cb.id
    LEFT JOIN service_booking sb ON i.service_booking_id = sb.id
    LEFT JOIN customer cust ON cb.customer_id = cust.id
    LEFT JOIN court c ON cb.court_id = c.id
    LEFT JOIN branch b ON c.branch_id = b.id
    LEFT JOIN employee emp ON i.employee_id = emp.id
    WHERE CAST(i.created_at AS DATE) BETWEEN @FromDate AND @ToDate
        AND (@Status IS NULL OR i.[status] = @Status)
        AND (@EmployeeId IS NULL OR i.employee_id = @EmployeeId)
        AND (@InvoiceId IS NULL OR i.id = @InvoiceId)
        AND (@CustomerName IS NULL OR cust.full_name LIKE N'%' + @CustomerName + N'%')
    ORDER BY i.created_at DESC;
END
GO
