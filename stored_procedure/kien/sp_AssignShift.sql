USE SportsCenterDB;
GO
/* * 3.2. Phân ca cho nhân viên (sp_AssignShift) */
CREATE OR ALTER PROCEDURE sp_AssignShift
    @EmployeeID INT,
    @WorkShiftID INT,
    @Note NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM work_shift WHERE id = @WorkShiftID)
            THROW 50006, N'Error: Work Shift ID not found.', 1;

        IF EXISTS (SELECT 1 FROM shift_assignment WHERE employee_id = @EmployeeID AND work_shift_id = @WorkShiftID)
            THROW 50007, N'Error: Employee already assigned to this shift.', 1;

        DECLARE @CurrentCount INT;
        DECLARE @RequiredCount INT;
        SELECT @CurrentCount = COUNT(*) FROM shift_assignment WHERE work_shift_id = @WorkShiftID;
        SELECT @RequiredCount = required_count FROM work_shift WHERE id = @WorkShiftID;

        IF @CurrentCount >= @RequiredCount
            THROW 50008, N'Error: Work shift is full.', 1;

        INSERT INTO shift_assignment (employee_id, work_shift_id, status, note)
        VALUES (@EmployeeID, @WorkShiftID, 'Assigned', @Note);
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO