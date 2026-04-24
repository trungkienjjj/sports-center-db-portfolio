USE SportsCenterDB;
GO

-- =============================================
-- 5. SP_CreateLeaveRequest
-- Mô tả: Nhân viên tạo đơn xin nghỉ phép
-- =============================================
CREATE OR ALTER PROCEDURE SP_CreateLeaveRequest
    @EmployeeId INT,
    @StartDate DATE,
    @EndDate DATE,
    @Reason NVARCHAR(1000) = NULL
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
    
    -- Kiểm tra ngày hợp lệ
    IF @StartDate > @EndDate
    BEGIN
        SELECT 
            0 AS Success,
            N'Ngày bắt đầu phải nhỏ hơn hoặc bằng ngày kết thúc' AS Message;
        RETURN;
    END
    
    -- Tạo đơn xin nghỉ phép
    INSERT INTO leave_request (
        created_at,
        start_date,
        end_date,
        approval_status,
        reason,
        creator_id
    )
    VALUES (
        GETDATE(), 
        @StartDate,
        @EndDate,
        N'Chờ duyệt',
        @Reason,
        @EmployeeId
    );
    
    SELECT 
        1 AS Success,
        N'Đơn xin nghỉ phép đã được tạo thành công' AS Message,
        SCOPE_IDENTITY() AS LeaveRequestId;
END
GO
