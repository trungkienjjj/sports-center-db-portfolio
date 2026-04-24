USE SportsCenterDB;
GO
/* * 3.1. Tạo ca làm việc (sp_CreateWorkShift) */
CREATE OR ALTER PROCEDURE sp_CreateWorkShift
    @Date DATE,
    @StartTime TIME,
    @EndTime TIME,
    @RequiredCount INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO work_shift (date, start_time, end_time, required_count)
        VALUES (@Date, @StartTime, @EndTime, @RequiredCount);
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO