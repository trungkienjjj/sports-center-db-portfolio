USE SportsCenterDB;
GO
/* * 2.1. Báo cáo doanh thu chi tiết (sp_ReportRevenue) */
CREATE OR ALTER PROCEDURE sp_ReportRevenue
    @StartDate DATE,
    @EndDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        b.name AS BranchName,
        YEAR(i.created_at) AS [Year],
        MONTH(i.created_at) AS [Month],
        ct.name AS CourtType,
        COUNT(DISTINCT i.id) AS TotalInvoices,
        ISNULL(SUM(i.total_amount), 0) AS TotalRevenue
    FROM invoice i
    JOIN court_booking cb ON i.court_booking_id = cb.id
    JOIN court c ON cb.court_id = c.id
    JOIN court_type ct ON c.court_type_id = ct.id
    JOIN branch b ON c.branch_id = b.id
    WHERE i.created_at BETWEEN @StartDate AND @EndDate
      AND i.status = 'Paid'
    GROUP BY b.name, YEAR(i.created_at), MONTH(i.created_at), ct.name
    ORDER BY b.name, [Year] DESC, [Month] DESC;
END;
GO