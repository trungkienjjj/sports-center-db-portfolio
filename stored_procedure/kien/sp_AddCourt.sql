USE SportsCenterDB;
GO

/* * 1.1. Thêm sân mới (sp_AddCourt) */
CREATE OR ALTER PROCEDURE sp_AddCourt
    @Name NVARCHAR(100),
    @Status NVARCHAR(50) = 'Available',
    @Capacity INT,
    @BaseHourlyPrice DECIMAL(10,2),
    @BranchID INT,
    @CourtTypeID INT,
    @MaintenanceDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @Status = 'Maintenance' AND @MaintenanceDate IS NULL
            THROW 50001, N'Error: Status is Maintenance but MaintenanceDate is NULL.', 1;

        INSERT INTO court (name, status, capacity, base_hourly_price, maintenance_date, branch_id, court_type_id)
        VALUES (@Name, @Status, @Capacity, @BaseHourlyPrice, @MaintenanceDate, @BranchID, @CourtTypeID);
        
        SELECT SCOPE_IDENTITY() AS NewCourtID;
    END TRY
    BEGIN CATCH
        THROW; 
    END CATCH
END;
GO