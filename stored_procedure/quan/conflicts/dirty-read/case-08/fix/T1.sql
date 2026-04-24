USE SportsCenterDB;
GO

/* * 1.2. Cập nhật thông tin sân (sp_UpdateCourt) */
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
        BEGIN TRANSACTION;  -- BẮT ĐẦU TRANSACTION
        
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
        
        -- Đợi 20 giây để T2 có thời gian đọc dirty data
        WAITFOR DELAY '00:00:20';
        
        -- Check ràng buộc sau khi update
        IF EXISTS (SELECT 1 FROM court WHERE id = @CourtID AND (capacity < 0 OR base_hourly_price < 0))
            THROW 50003, N'Error: Capacity and Base Hourly Price cannot be negative.', 1;
        
        PRINT N'T1: Đã ROLLBACK - Giá không được cập nhật!';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- Reset bảng
EXEC sp_MSforeachtable 'ALTER TABLE ? NOCHECK CONSTRAINT ALL';
DELETE FROM booking_slots;  
DELETE FROM court_booking;
EXEC sp_MSforeachtable 'ALTER TABLE ? CHECK CONSTRAINT ALL';
UPDATE court SET base_hourly_price = 150000 WHERE id = 1;
-- Kiểm tra giá hiện tại
SELECT id, name, base_hourly_price 
FROM court 
WHERE id = 1;

-- Chạy sp
EXEC sp_UpdateCourt 
    @CourtID = 1,
    @Name = N'Sân A1',
    @Status = N'Sẵn sàng',
    @Capacity = 10,
    @BaseHourlyPrice = -200000.00;

SELECT id, name, base_hourly_price 
FROM court 
WHERE id = 1;