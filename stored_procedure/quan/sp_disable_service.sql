USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - XÓA DỊCH VỤ KHỎI CHI NHÁNH
 * =================================================================================
 */

/*
 * =================================================================================
 * STORED PROCEDURE BỔ SUNG - VÔ HIỆU HÓA DỊCH VỤ
 * =================================================================================
 */

/*
 * Vô hiệu hóa dịch vụ chi nhánh (sp_disable_branch_service)
 * 
 * Chức năng:
 *   - Đổi trạng thái dịch vụ thành "Hết" thay vì xóa
 *   - An toàn hơn khi dịch vụ đã có booking
 *   - Giữ lại lịch sử và dữ liệu
 *
 * Tham số đầu vào:
 *   @BranchServiceID  INT : ID của dịch vụ chi nhánh
 *
 * Ví dụ:
 *   EXEC sp_disable_branch_service @BranchServiceID = 5;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_disable_branch_service
    @BranchServiceID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @BranchName   NVARCHAR(255),
        @ServiceName  NVARCHAR(255),
        @CurrentStatus NVARCHAR(50);

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tồn tại
         *-----------------------------------------------------*/
        IF @BranchServiceID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID dịch vụ chi nhánh không được để trống.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        SELECT 
            @BranchName = b.[name],
            @ServiceName = s.[name],
            @CurrentStatus = bs.[status]
        FROM branch_service bs
        JOIN branch b ON bs.branch_id = b.id
        JOIN [service] s ON bs.service_id = s.id
        WHERE bs.id = @BranchServiceID;

        IF @BranchName IS NULL
        BEGIN
            SELECT 0 AS Success, N'Dịch vụ chi nhánh không tồn tại.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra trạng thái hiện tại
         *-----------------------------------------------------*/
        IF @CurrentStatus = N'Hết'
        BEGIN
            SELECT 
                0 AS Success,
                N'Dịch vụ "' + @ServiceName + N'" ở chi nhánh "' + @BranchName + N'" đã ở trạng thái "Hết" rồi.' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Cập nhật trạng thái
         *-----------------------------------------------------*/
        UPDATE branch_service
        SET [status] = N'Hết',
            current_stock = 0  -- Đặt tồn kho về 0
        WHERE id = @BranchServiceID;

        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Đã vô hiệu hóa dịch vụ "' + @ServiceName + N'" ở chi nhánh "' + @BranchName 
            + N'". Trạng thái: Hết (Tồn kho: 0)' AS Message;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi vô hiệu hóa dịch vụ: ' + ERROR_MESSAGE() AS Message;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO 2 STORED PROCEDURES ===';
PRINT N'1. sp_delete_branch_service - Xóa dịch vụ (chỉ khi chưa dùng)';
PRINT N'2. sp_disable_branch_service - Vô hiệu hóa dịch vụ (an toàn hơn)';