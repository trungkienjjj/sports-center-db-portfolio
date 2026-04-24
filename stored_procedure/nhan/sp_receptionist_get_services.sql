USE SportsCenterDB;
GO

-- Xem các dịch vụ của chi nhánh
DROP PROCEDURE IF EXISTS sp_receptionist_get_services;
GO

CREATE PROCEDURE sp_receptionist_get_services
    @branch_id INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN
            SELECT bs.id, s.unit, s.name, s.rental_type, bs.unit_price, bs.current_stock, bs.min_stock_threshold, bs.status
            FROM branch_service bs
                JOIN service s ON bs.service_id = s.id
            WHERE bs.branch_id = @branch_id;
        COMMIT
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;