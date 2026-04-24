USE SportsCenterDB;
GO

/* 2.2. Duyệt đơn xin nghỉ phép (sp_ApproveLeaveRequest) */
CREATE OR ALTER PROCEDURE sp_ApproveLeaveRequest
    @RequestID INT,
    @ApproverID INT,
    @Status NVARCHAR(50),
    @Reason NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- Tùy chọn mức cô lập (Read Committed là mặc định)
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
        BEGIN TRANSACTION;
        
        -- 1. Kiểm tra đơn tồn tại
        IF NOT EXISTS (SELECT 1 FROM leave_request WHERE id = @RequestID)
            THROW 50003, N'Error: Leave Request ID not found.', 1;

        -- 2. Validate lý do từ chối
        IF @Status = 'Rejected' AND (@Reason IS NULL OR LEN(@Reason) = 0)
            THROW 50004, N'Error: Rejection requires a reason.', 1;

        -- 3. Lấy thông tin chi tiết của đơn
        DECLARE @ReplacerID INT;
        DECLARE @EmployeeID INT;
        DECLARE @WorkShiftID INT;
        DECLARE @LeaveDate DATE; -- Biến tạm để lấy ngày nghỉ

        SELECT 
            @ReplacerID = replacer_id,
            @EmployeeID = creator_id, -- [FIX 1]: Sửa employee_id thành creator_id
            @LeaveDate = start_date   -- [FIX 2]: Lấy ngày nghỉ thay vì work_shift_id
        FROM leave_request 
        WHERE id = @RequestID;

        -- [LOGIC BỔ SUNG]: Tìm WorkShiftID dựa trên ngày nghỉ
        -- Lấy ID ca làm việc trong bảng work_shift tương ứng với ngày nghỉ
        SELECT TOP 1 @WorkShiftID = id 
        FROM work_shift 
        WHERE [date] = @LeaveDate;

        -- Validate người thay thế
        IF @Status = 'Approved' AND @ReplacerID IS NULL
            THROW 50005, N'Error: Cannot approve without a replacer.', 1;

        -- 4. Cập nhật trạng thái đơn
        UPDATE leave_request
        SET approval_status = @Status, 
            approver_id = @ApproverID,
            reason = ISNULL(@Reason, reason)
        WHERE id = @RequestID;

        -- 5. [PHANTOM LOGIC] Tự động chèn lịch nghỉ 'Absent'
        IF @Status = 'Approved'
        BEGIN
            -- Kiểm tra nếu tìm được WorkShiftID thì mới Insert
            IF @WorkShiftID IS NOT NULL
            BEGIN
                INSERT INTO shift_assignment (employee_id, work_shift_id, status)
                VALUES (@EmployeeID, @WorkShiftID, 'Absent');
            END
            ELSE
            BEGIN
                -- (Tùy chọn) In cảnh báo nếu không tìm thấy ca làm việc cho ngày nghỉ này
                PRINT N'Warning: Không tìm thấy WorkShiftID cho ngày ' + CAST(@LeaveDate AS NVARCHAR(20));
            END
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO