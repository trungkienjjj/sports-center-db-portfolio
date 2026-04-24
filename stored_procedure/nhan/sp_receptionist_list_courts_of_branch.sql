USE SportsCenterDB;
GO

-- Lấy danh sách các sân của một chi nhánh và một loại sân (có thể gộp với SP tìm sân của KH)
DROP PROCEDURE IF EXISTS sp_receptionist_list_courts_of_branch;
GO

CREATE PROCEDURE sp_receptionist_list_courts_of_branch
    @branch_id INT,
    @court_type_id INT
AS
BEGIN
    BEGIN TRY
        BEGIN TRAN;   -- Start transaction

        SELECT c.id, c.status, c.name
        FROM court c
        WHERE c.branch_id = @branch_id AND c.court_type_id = @court_type_id;
        
        COMMIT;       -- Success
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK;
        PRINT 'Lỗi: ' + ERROR_MESSAGE();
    END CATCH
END;