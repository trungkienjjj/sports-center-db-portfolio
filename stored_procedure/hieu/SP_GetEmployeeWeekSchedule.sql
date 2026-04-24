USE SportsCenterDB;
GO

-- =============================================
-- 4. SP_GetEmployeeWeekSchedule
-- Mô tả: Xem lịch làm việc của nhân viên theo tuần
-- Tham số: @FromDate, @ToDate (kiểu DATE)
-- =============================================

--4.1 Xem lịch làm việc của nhân viên theo tuần
CREATE OR ALTER PROCEDURE SP_GetEmployeeWeekSchedule
    @EmployeeId INT,
    @FromDate DATE,
    @ToDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra khoảng thời gian hợp lệ
    IF @FromDate > @ToDate
    BEGIN
        SELECT 
            0 AS Success,
            N'Ngày bắt đầu phải nhỏ hơn hoặc bằng ngày kết thúc' AS Message;
        RETURN;
    END
    
    -- Result Set 1: Thống kê tổng quan số lượng ca trực
    SELECT 
        COUNT(*) AS TotalShifts, -- Tổng ca trực
        SUM(CASE WHEN sa.[status] = N'Đã chấm công' THEN 1 ELSE 0 END) AS ConfirmedShifts, -- Đã xác nhận
        SUM(CASE WHEN sa.[status] = N'Đã phân công' THEN 1 ELSE 0 END) AS PendingShifts, -- Chờ xác nhận
        SUM(CASE WHEN sa.[status] IN (N'Nghỉ có phép', N'Nghỉ không phép') THEN 1 ELSE 0 END) AS CancelledShifts -- Đã hủy
    FROM shift_assignment sa
    INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
    WHERE ws.[date] BETWEEN @FromDate AND @ToDate
        AND sa.employee_id = @EmployeeId;
    
    -- Result Set 2: Chi tiết lịch làm việc theo tuần
    SELECT 
        ws.[date] AS WorkDate,
        DATENAME(WEEKDAY, ws.[date]) AS DayOfWeek,
        DATEPART(WEEKDAY, ws.[date]) AS DayNumber,
        ws.start_time AS StartTime,
        ws.end_time AS EndTime,
        sa.[status] AS ShiftStatus,
        sa.note AS Note,
        r.[name] AS EmployeePosition, -- Lấy chức vụ từ bảng role
        b.[name] AS BranchName
    FROM shift_assignment sa
    INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
    INNER JOIN employee e ON sa.employee_id = e.id
    INNER JOIN branch b ON e.branch_id = b.id
    INNER JOIN account a ON e.user_id = a.id
    INNER JOIN [role] r ON a.role_id = r.id
    WHERE ws.[date] BETWEEN @FromDate AND @ToDate
        AND sa.employee_id = @EmployeeId
    ORDER BY ws.[date], ws.start_time;
END
GO

--4.2 Xem danh sách lịch làm việc của nhân viên theo tháng năm
CREATE OR ALTER PROCEDURE SP_GetEmployeeMonthSchedule
    @EmployeeId INT,
    @Month INT,
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra tháng hợp lệ (1-12)
    IF @Month < 1 OR @Month > 12
    BEGIN
        SELECT 
            0 AS Success,
            N'Tháng phải trong khoảng từ 1 đến 12' AS Message;
        RETURN;
    END

    -- Tính ngày đầu và cuối tháng
    DECLARE @StartDate DATE = DATEFROMPARTS(@Year, @Month, 1);
    DECLARE @EndDate DATE = EOMONTH(@StartDate);
    
    -- Result Set 1: Thống kê tổng quan số lượng ca trực
    SELECT 
        COUNT(*) AS TotalShifts, -- Tổng ca trực
        SUM(CASE WHEN sa.[status] = N'Đã chấm công' THEN 1 ELSE 0 END) AS ConfirmedShifts, -- Đã xác nhận
        SUM(CASE WHEN sa.[status] = N'Đã phân công' THEN 1 ELSE 0 END) AS PendingShifts, -- Chờ xác nhận
        SUM(CASE WHEN sa.[status] IN (N'Nghỉ có phép', N'Nghỉ không phép') THEN 1 ELSE 0 END) AS CancelledShifts, -- Đã hủy
        COUNT(DISTINCT ws.[date]) AS TotalWorkDays, -- Tổng số ngày làm việc
        @Month AS [Month],
        @Year AS [Year]
    FROM shift_assignment sa
    INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
    WHERE ws.[date] BETWEEN @StartDate AND @EndDate
        AND sa.employee_id = @EmployeeId;
    
    -- Result Set 2: Chi tiết các ca làm việc trong tháng
    SELECT 
        ws.[date] AS WorkDate,
        DATENAME(WEEKDAY, ws.[date]) AS DayOfWeek,
        DATEPART(WEEKDAY, ws.[date]) AS DayNumber,
        ws.start_time AS StartTime,
        ws.end_time AS EndTime,
        sa.[status] AS ShiftStatus,
        sa.note AS Note,
        r.[name] AS EmployeePosition, -- Lấy chức vụ từ bảng role
        b.[name] AS BranchName
    FROM shift_assignment sa
    INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
    INNER JOIN employee e ON sa.employee_id = e.id
    INNER JOIN branch b ON e.branch_id = b.id
    INNER JOIN account a ON e.user_id = a.id
    INNER JOIN [role] r ON a.role_id = r.id
    WHERE ws.[date] BETWEEN @StartDate AND @EndDate
        AND sa.employee_id = @EmployeeId
    ORDER BY ws.[date], ws.start_time;
END
GO

--4.3 Xem lịch nghỉ phép của nhân viên
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetEmployeeLeaveRequests
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiểm tra nhân viên tồn tại
    IF NOT EXISTS (SELECT 1 FROM employee WHERE id = @EmployeeId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Nhân viên không tồn tại' AS Message;
        RETURN;
    END
    
    -- Result Set 1: Thống kê tổng quan đơn nghỉ phép
    SELECT 
        COUNT(*) AS TotalRequests, -- Tổng đơn nghỉ phép
        SUM(CASE WHEN approval_status = N'Chờ duyệt' THEN 1 ELSE 0 END) AS PendingRequests, -- Chờ duyệt
        SUM(CASE WHEN approval_status = N'Đã duyệt' THEN 1 ELSE 0 END) AS ApprovedRequests, -- Đã duyệt
        SUM(CASE WHEN approval_status = N'Từ chối' THEN 1 ELSE 0 END) AS RejectedRequests, -- Từ chối
        SUM(CASE 
            WHEN approval_status = N'Đã duyệt' 
                AND YEAR(start_date) = YEAR(GETDATE())
            THEN DATEDIFF(DAY, start_date, end_date) + 1 
            ELSE 0 
        END) AS TotalApprovedDaysThisYear -- Tổng số ngày nghỉ đã duyệt trong năm
    FROM leave_request
    WHERE creator_id = @EmployeeId;
    
    -- Result Set 2: Chi tiết các đơn nghỉ phép
    SELECT 
        lr.start_date AS StartDate,
        lr.end_date AS EndDate,
        lr.approval_status AS ApprovalStatus,
        lr.reason AS Reason,
        approver.full_name AS ApproverName,
        r_approver.[name] AS ApproverPosition, -- Chức vụ người duyệt
        replacer.full_name AS ReplacerName,
        r_replacer.[name] AS ReplacerPosition, -- Chức vụ người thay thế
        lr.created_at AS CreatedAt
    FROM leave_request lr
    LEFT JOIN employee approver ON lr.approver_id = approver.id
    LEFT JOIN account a_approver ON approver.user_id = a_approver.id
    LEFT JOIN [role] r_approver ON a_approver.role_id = r_approver.id
    LEFT JOIN employee replacer ON lr.replacer_id = replacer.id
    LEFT JOIN account a_replacer ON replacer.user_id = a_replacer.id
    LEFT JOIN [role] r_replacer ON a_replacer.role_id = r_replacer.id
    WHERE lr.creator_id = @EmployeeId
    ORDER BY lr.created_at DESC;
END
GO
