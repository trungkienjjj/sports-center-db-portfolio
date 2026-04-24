/* * 3.3. Theo dõi giờ làm (sp_TrackWorkingHours) */
CREATE OR ALTER PROCEDURE sp_TrackWorkingHours
    @Month INT,
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT 
        e.id AS EmployeeID,
        e.full_name AS EmployeeName,
        COUNT(ws.id) AS TotalShifts,
        ISNULL(SUM(DATEDIFF(HOUR, ws.start_time, ws.end_time)), 0) AS TotalHours
    FROM shift_assignment sa
    JOIN work_shift ws ON sa.work_shift_id = ws.id
    JOIN employee e ON sa.employee_id = e.id
    WHERE MONTH(ws.date) = @Month 
      AND YEAR(ws.date) = @Year
      AND sa.status IN ('Assigned', 'Completed')
    GROUP BY e.id, e.full_name;
END;
GO