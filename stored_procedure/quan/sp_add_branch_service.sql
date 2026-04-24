USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - THÊM DỊCH VỤ CHO CHI NHÁNH
 * =================================================================================
 */

/*
 * Thêm dịch vụ vào chi nhánh (sp_add_branch_service)
 * 
 * Chức năng:
 *   - Manager thêm dịch vụ mới vào chi nhánh của mình
 *   - Kiểm tra dịch vụ chưa tồn tại ở chi nhánh đó
 *   - Kiểm tra tính hợp lệ của giá, tồn kho, ngưỡng tồn kho
 *   - Tự động xác định trạng thái dựa trên tồn kho
 *   - Trả về thông tin chi tiết dịch vụ vừa thêm
 *
 * Tham số đầu vào:
 *   @BranchID          INT           : ID chi nhánh (bắt buộc)
 *   @ServiceID         INT           : ID dịch vụ (bắt buộc)
 *   @UnitPrice         DECIMAL(10,2) : Đơn giá (phải >= 0)
 *   @CurrentStock      INT           : Tồn kho hiện tại (phải >= 0)
 *   @MinStockThreshold INT           : Ngưỡng tồn kho tối thiểu (phải >= 0)
 *
 * Kết quả trả về:
 *   Success, Message, BranchServiceID, BranchName, ServiceName, Status
 *
 * Ví dụ:
 *   -- Thêm dịch vụ "Thuê Bóng Đá" vào chi nhánh HCM
 *   EXEC sp_add_branch_service
 *       @BranchID = 1,
 *       @ServiceID = 1,
 *       @UnitPrice = 20000,
 *       @CurrentStock = 50,
 *       @MinStockThreshold = 10;
 *
 * Lưu ý:
 *   - Mỗi dịch vụ chỉ được thêm 1 lần vào mỗi chi nhánh (UNIQUE constraint)
 *   - Trạng thái tự động: "Còn" nếu stock > 0, "Hết" nếu stock = 0
 *   - Chỉ Manager của chi nhánh hoặc Admin mới có quyền thực hiện
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_add_branch_service
    @BranchID          INT,
    @ServiceID         INT,
    @UnitPrice         DECIMAL(10, 2),
    @CurrentStock      INT,
    @MinStockThreshold INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @NewBranchServiceID INT,
        @BranchName         NVARCHAR(255),
        @ServiceName        NVARCHAR(255),
        @ServiceStockType   NVARCHAR(100),
        @AutoStatus         NVARCHAR(50);

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @BranchID IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'ID chi nhánh không được để trống.' AS Message,
                NULL AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @ServiceID IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'ID dịch vụ không được để trống.' AS Message,
                NULL AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @UnitPrice IS NULL OR @CurrentStock IS NULL OR @MinStockThreshold IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Đơn giá, tồn kho và ngưỡng tồn kho không được để trống.' AS Message,
                NULL AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra chi nhánh tồn tại
         *-----------------------------------------------------*/
        SELECT @BranchName = [name]
        FROM branch
        WHERE id = @BranchID;

        IF @BranchName IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Chi nhánh không tồn tại.' AS Message,
                NULL AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra dịch vụ tồn tại
         *-----------------------------------------------------*/
        SELECT 
            @ServiceName = [name],
            @ServiceStockType = stock_type
        FROM [service]
        WHERE id = @ServiceID;

        IF @ServiceName IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Dịch vụ không tồn tại.' AS Message,
                NULL AS BranchServiceID,
                @BranchName AS BranchName,
                NULL AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Kiểm tra dịch vụ đã tồn tại ở chi nhánh chưa
         *-----------------------------------------------------*/
        IF EXISTS(
            SELECT 1 
            FROM branch_service 
            WHERE branch_id = @BranchID AND service_id = @ServiceID
        )
        BEGIN
            SELECT 
                0 AS Success,
                N'Dịch vụ "' + @ServiceName + N'" đã tồn tại ở chi nhánh "' + @BranchName + N'". Vui lòng sử dụng chức năng cập nhật.' AS Message,
                NULL AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 5. Kiểm tra giá trị hợp lệ (theo constraint R1117)
         *-----------------------------------------------------*/
        IF @UnitPrice < 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Đơn giá phải là số không âm.' AS Message,
                NULL AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @CurrentStock < 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Tồn kho hiện tại phải là số không âm.' AS Message,
                NULL AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @MinStockThreshold < 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Ngưỡng tồn kho tối thiểu phải là số không âm.' AS Message,
                NULL AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS Status;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 6. Kiểm tra logic nghiệp vụ
         *-----------------------------------------------------*/
        -- Cảnh báo nếu tồn kho < ngưỡng tối thiểu (không chặn)
        IF @CurrentStock < @MinStockThreshold
        BEGIN
            PRINT N'⚠️ Cảnh báo: Tồn kho hiện tại (' + CAST(@CurrentStock AS NVARCHAR(10)) 
                + N') thấp hơn ngưỡng tối thiểu (' + CAST(@MinStockThreshold AS NVARCHAR(10)) + N').';
        END

        -- Kiểm tra stock type hợp lý
        IF @ServiceStockType = N'khong_gioi_han' AND @CurrentStock > 0
        BEGIN
            PRINT N'⚠️ Lưu ý: Dịch vụ này không giới hạn tồn kho. Tồn kho hiện tại sẽ không được sử dụng.';
        END

        IF @ServiceStockType = N'hlv_trong_tai' AND (@CurrentStock > 0 OR @MinStockThreshold > 0)
        BEGIN
            PRINT N'⚠️ Lưu ý: Dịch vụ HLV/Trọng tài không cần quản lý tồn kho.';
        END

        /*------------------------------------------------------
         * 7. Xác định trạng thái tự động
         *-----------------------------------------------------*/
        -- Trạng thái "Còn" nếu stock > 0, "Hết" nếu stock = 0
        IF @CurrentStock > 0
            SET @AutoStatus = N'Còn';
        ELSE
            SET @AutoStatus = N'Hết';

        /*------------------------------------------------------
         * 8. Thêm dịch vụ vào chi nhánh
         *-----------------------------------------------------*/
        INSERT INTO branch_service (
            unit_price,
            current_stock,
            min_stock_threshold,
            [status],
            branch_id,
            service_id
        )
        VALUES (
            @UnitPrice,
            @CurrentStock,
            @MinStockThreshold,
            @AutoStatus,
            @BranchID,
            @ServiceID
        );

        SET @NewBranchServiceID = SCOPE_IDENTITY();

        /*------------------------------------------------------
         * 9. Commit và trả về kết quả
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Thêm dịch vụ "' + @ServiceName + N'" vào chi nhánh "' + @BranchName + N'" thành công.' AS Message,
            @NewBranchServiceID AS BranchServiceID,
            @BranchName AS BranchName,
            @ServiceName AS ServiceName,
            @AutoStatus AS Status;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi thêm dịch vụ: ' + ERROR_MESSAGE() AS Message,
            NULL AS BranchServiceID,
            NULL AS BranchName,
            NULL AS ServiceName,
            NULL AS Status;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: sp_add_branch_service ===';
GO