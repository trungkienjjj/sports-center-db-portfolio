USE SportsCenterDB;
GO

-- =============================================
-- 1. SP_GetBranchOverview
-- Mô tả: Xem thông tin tổng quan về chi nhánh (cho khách hàng chưa login)
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetBranchOverview
    @BranchId INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        b.id AS BranchId,
        b.[name] AS BranchName,
        b.[address] AS Address,
        b.hotline AS Hotline,
        b.open_time AS OpenTime,
        b.close_time AS CloseTime,
        COUNT(DISTINCT c.id) AS TotalCourts,
        AVG(c.base_hourly_price) AS AvgCourtPrice
    FROM branch b
    LEFT JOIN court c ON b.id = c.branch_id
    LEFT JOIN court_type ct ON c.court_type_id = ct.id
    WHERE (@BranchId IS NULL OR b.id = @BranchId)
    GROUP BY b.id, b.[name], b.[address], b.hotline, b.open_time, b.close_time
    ORDER BY b.id;
END
GO
