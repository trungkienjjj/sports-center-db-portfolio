USE SportsCenterDB;
GO
/* * 4.2. Lấy chi tiết sân cho màn hình đặt sân (sp_GetCourtDetailForBooking)
 * UPDATE: Thêm open_time, close_time để UI vẽ lưới giờ
 */
CREATE OR ALTER PROCEDURE sp_GetCourtDetailForBooking
    @CourtID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        c.id, 
        c.status, 
        c.base_hourly_price, 
        ct.name AS CourtTypeName, 
        ct.rent_duration, 
        b.name AS BranchName,
        b.open_time,  -- [NEW] Giờ mở cửa
        b.close_time  -- [NEW] Giờ đóng cửa
    FROM court c
    JOIN court_type ct ON c.court_type_id = ct.id
    JOIN branch b ON c.branch_id = b.id
    WHERE c.id = @CourtID;
END;
GO