USE SportsCenterDB;
GO
/* * 4.3. Lấy lịch đã đặt trong ngày (sp_GetBookedSlotsByDate) */
CREATE OR ALTER PROCEDURE sp_GetBookedSlotsByDate
    @CourtID INT,
    @ViewDate DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT bs.start_time, bs.end_time, 
           CASE WHEN cb.status = 'Paid' THEN 'Booked' WHEN cb.status = 'Held' THEN 'Pending' ELSE 'Unknown' END AS SlotStatus
    FROM booking_slots bs
    JOIN court_booking cb ON bs.court_booking_id = cb.id
    WHERE cb.court_id = @CourtID AND CAST(bs.start_time AS DATE) = @ViewDate AND cb.status <> 'Cancelled';
END;
GO