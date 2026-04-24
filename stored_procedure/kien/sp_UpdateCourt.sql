USE SportsCenterDB;
GO

CREATE OR ALTER PROCEDURE sp_UpdateCourt
    @CourtID INT,
    @Name NVARCHAR(100),
    @Status NVARCHAR(50),
    @Capacity INT,
    @BaseHourlyPrice DECIMAL(10,2),
    @MaintenanceDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM court WHERE id = @CourtID)
            THROW 50002, N'Error: Court ID not found.', 1;

        IF @Status = 'Maintenance' AND @MaintenanceDate IS NULL
            THROW 50001, N'Error: Status is Maintenance but MaintenanceDate is NULL.', 1;

        UPDATE court
        SET name = @Name,
            status = @Status,
            capacity = @Capacity,
            base_hourly_price = @BaseHourlyPrice,
            maintenance_date = @MaintenanceDate
        WHERE id = @CourtID;

        -- Check ràng buộc sau khi update
        IF EXISTS (SELECT 1 FROM court WHERE id = @CourtID AND (capacity < 0 OR base_hourly_price < 0))
            THROW 50003, N'Error: Capacity and Base Hourly Price cannot be negative.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO