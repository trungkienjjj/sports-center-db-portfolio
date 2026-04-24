USE SportsCenterDB;
GO
/* * 1.3. Xóa sân (sp_DeleteCourt) */
CREATE OR ALTER PROCEDURE sp_DeleteCourt
    @CourtID INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF EXISTS (SELECT 1 FROM court_booking WHERE court_id = @CourtID)
        BEGIN
            UPDATE court SET status = 'Maintenance' WHERE id = @CourtID;
            PRINT N'Info: Soft deleted (Changed status to Maintenance).';
        END
        ELSE
        BEGIN
            DELETE FROM court WHERE id = @CourtID;
            PRINT N'Info: Hard deleted successfully.';
        END
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO