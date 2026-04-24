USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - CẬP NHẬT THÔNG TIN DỊCH VỤ CHI NHÁNH
 * Người thực hiện: [Tên bạn]
 * Ngày cập nhật: 10/12/2025
 * =================================================================================
 */

/*
 * Cập nhật thông tin dịch vụ chi nhánh (USP_UPDATE_BRANCH_SERVICE)
 * 
 * Chức năng:
 *   - Manager cập nhật giá, tồn kho (tăng/giảm), ngưỡng tồn kho, trạng thái của dịch vụ
 *   - Hỗ trợ cập nhật một phần (chỉ cập nhật trường được truyền vào)
 *   - Kiểm tra tính hợp lệ của giá trị
 *   - Cảnh báo nghiệp vụ (tồn kho thấp, thay đổi giá...)
 *   - Trả về thông tin chi tiết về các trường đã cập nhật
 *
 * Tham số đầu vào:
 *   @BranchServiceID   INT              : ID dịch vụ chi nhánh (bắt buộc)
 *   @UnitPrice         DECIMAL(10,2) = NULL : Đơn giá mới
 *   @StockQuantity     INT = NULL           : Số lượng tăng (+) hoặc giảm (-) tồn kho
 *   @MinStockThreshold INT = NULL           : Ngưỡng tồn kho mới
 *   @Status            NVARCHAR(50) = NULL  : Trạng thái mới (Còn/Hết)
 *
 * Kết quả trả về:
 *   Success, Message, BranchServiceID, BranchName, ServiceName, UpdatedFields, Warnings
 *
 * Ví dụ:
 *   -- Tăng giá và tăng tồn kho thêm 50
 *   EXEC USP_UPDATE_BRANCH_SERVICE
 *       @BranchServiceID = 5,
 *       @UnitPrice = 25000,
 *       @StockQuantity = 50;
 *
 *   -- Giảm tồn kho đi 20
 *   EXEC USP_UPDATE_BRANCH_SERVICE
 *       @BranchServiceID = 5,
 *       @StockQuantity = -20;
 *
 *   -- Chỉ đổi trạng thái
 *   EXEC USP_UPDATE_BRANCH_SERVICE
 *       @BranchServiceID = 5,
 *       @Status = N'Hết';
 *
 * Lưu ý:
 *   - Trạng thái chỉ chấp nhận: "Còn" hoặc "Hết"
 *   - Giá, ngưỡng phải >= 0
 *   - StockQuantity có thể âm (giảm) hoặc dương (tăng)
 *   - Tồn kho sau khi cập nhật không được âm
 *   - Tự động cảnh báo nếu tồn kho < ngưỡng
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE USP_UPDATE_BRANCH_SERVICE
    @BranchServiceID   INT,
    @UnitPrice         DECIMAL(10, 2) = NULL,
    @StockQuantity     INT = NULL,
    @MinStockThreshold INT = NULL,
    @Status            NVARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @BranchName        NVARCHAR(255),
        @ServiceName       NVARCHAR(255),
        @OldUnitPrice      DECIMAL(10, 2),
        @OldCurrentStock   INT,
        @NewCurrentStock   INT,
        @OldMinThreshold   INT,
        @NewMinThreshold   INT,
        @OldStatus         NVARCHAR(50),
        @UpdatedFields     NVARCHAR(MAX) = N'',
        @Warnings          NVARCHAR(MAX) = N'',
        @UpdateCount       INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra tham số bắt buộc
         *-----------------------------------------------------*/
        IF @BranchServiceID IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'ID dịch vụ chi nhánh không được để trống.' AS Message,
                NULL AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 2. Kiểm tra dịch vụ chi nhánh tồn tại và lấy thông tin cũ
         *-----------------------------------------------------*/
        SELECT 
            @BranchName = b.[name],
            @ServiceName = s.[name],
            @OldUnitPrice = bs.unit_price,
            @OldCurrentStock = bs.current_stock,
            @OldMinThreshold = bs.min_stock_threshold,
            @OldStatus = bs.[status]
        FROM branch_service bs
        JOIN branch b ON bs.branch_id = b.id
        JOIN [service] s ON bs.service_id = s.id
        WHERE bs.id = @BranchServiceID;

        IF @BranchName IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Dịch vụ chi nhánh không tồn tại.' AS Message,
                @BranchServiceID AS BranchServiceID,
                NULL AS BranchName,
                NULL AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra giá trị hợp lệ (theo constraint R1117)
         *-----------------------------------------------------*/
        IF @UnitPrice IS NOT NULL AND @UnitPrice < 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Đơn giá phải là số không âm.' AS Message,
                @BranchServiceID AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra tồn kho sau khi cộng/trừ không được âm
        IF @StockQuantity IS NOT NULL
        BEGIN
            SET @NewCurrentStock = @OldCurrentStock + @StockQuantity;
            
            IF @NewCurrentStock < 0
            BEGIN
                SELECT 
                    0 AS Success,
                    N'Không thể giảm tồn kho. Tồn kho hiện tại: ' + CAST(@OldCurrentStock AS NVARCHAR(10)) 
                    + N', Số lượng giảm: ' + CAST(ABS(@StockQuantity) AS NVARCHAR(10))
                    + N'. Tồn kho sau cập nhật sẽ âm (' + CAST(@NewCurrentStock AS NVARCHAR(10)) + N').' AS Message,
                    @BranchServiceID AS BranchServiceID,
                    @BranchName AS BranchName,
                    @ServiceName AS ServiceName,
                    NULL AS UpdatedFields,
                    NULL AS Warnings;
                ROLLBACK TRANSACTION;
                RETURN;
            END
        END

        IF @MinStockThreshold IS NOT NULL AND @MinStockThreshold < 0
        BEGIN
            SELECT 
                0 AS Success,
                N'Ngưỡng tồn kho phải là số không âm.' AS Message,
                @BranchServiceID AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        IF @Status IS NOT NULL AND @Status NOT IN (N'Còn', N'Hết')
        BEGIN
            SELECT 
                0 AS Success,
                N'Trạng thái chỉ được là "Còn" hoặc "Hết".' AS Message,
                @BranchServiceID AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Kiểm tra có cập nhật gì không
         *-----------------------------------------------------*/
        IF @UnitPrice IS NULL AND @StockQuantity IS NULL AND @MinStockThreshold IS NULL AND @Status IS NULL
        BEGIN
            SELECT 
                0 AS Success,
                N'Không có trường nào được cập nhật. Vui lòng truyền ít nhất một giá trị mới.' AS Message,
                @BranchServiceID AS BranchServiceID,
                @BranchName AS BranchName,
                @ServiceName AS ServiceName,
                NULL AS UpdatedFields,
                NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 5. Cập nhật dữ liệu
         *-----------------------------------------------------*/
        UPDATE branch_service
        SET
            unit_price = CASE WHEN @UnitPrice IS NOT NULL THEN @UnitPrice ELSE unit_price END,
            current_stock = CASE WHEN @StockQuantity IS NOT NULL THEN current_stock + @StockQuantity ELSE current_stock END,
            min_stock_threshold = CASE WHEN @MinStockThreshold IS NOT NULL THEN @MinStockThreshold ELSE min_stock_threshold END,
            [status] = CASE WHEN @Status IS NOT NULL THEN @Status ELSE [status] END
        WHERE id = @BranchServiceID;

        /*------------------------------------------------------
         * 6. Ghi nhận các trường đã cập nhật
         *-----------------------------------------------------*/
        IF @UnitPrice IS NOT NULL
        BEGIN
            SET @UpdatedFields = @UpdatedFields + N'UnitPrice (' 
                + FORMAT(@OldUnitPrice, 'N0') + N' → ' 
                + FORMAT(@UnitPrice, 'N0') + N'), ';
            SET @UpdateCount = @UpdateCount + 1;
        END

        IF @StockQuantity IS NOT NULL
        BEGIN
            DECLARE @StockChangeText NVARCHAR(50);
            IF @StockQuantity > 0
                SET @StockChangeText = N'+' + CAST(@StockQuantity AS NVARCHAR(10));
            ELSE
                SET @StockChangeText = CAST(@StockQuantity AS NVARCHAR(10));
                
            SET @UpdatedFields = @UpdatedFields + N'CurrentStock (' 
                + CAST(@OldCurrentStock AS NVARCHAR(10)) + N' ' + @StockChangeText + N' → ' 
                + CAST(@NewCurrentStock AS NVARCHAR(10)) + N'), ';
            SET @UpdateCount = @UpdateCount + 1;
        END

        IF @MinStockThreshold IS NOT NULL
        BEGIN
            SET @UpdatedFields = @UpdatedFields + N'MinStockThreshold (' 
                + CAST(@OldMinThreshold AS NVARCHAR(10)) + N' → ' 
                + CAST(@MinStockThreshold AS NVARCHAR(10)) + N'), ';
            SET @UpdateCount = @UpdateCount + 1;
        END

        IF @Status IS NOT NULL
        BEGIN
            SET @UpdatedFields = @UpdatedFields + N'Status (' 
                + @OldStatus + N' → ' + @Status + N'), ';
            SET @UpdateCount = @UpdateCount + 1;
        END

        -- Bỏ dấu phẩy cuối
        IF LEN(@UpdatedFields) > 0
            SET @UpdatedFields = LEFT(@UpdatedFields, LEN(@UpdatedFields) - 2);

        /*------------------------------------------------------
         * 7. Tạo cảnh báo nghiệp vụ
         *-----------------------------------------------------*/
        -- Lấy giá trị mới sau khi update
        IF @StockQuantity IS NULL
            SET @NewCurrentStock = @OldCurrentStock;
            
        SET @NewMinThreshold = ISNULL(@MinStockThreshold, @OldMinThreshold);

        -- Cảnh báo: Tồn kho thấp hơn ngưỡng
        IF @NewCurrentStock < @NewMinThreshold
        BEGIN
            SET @Warnings = @Warnings + N'⚠️ Tồn kho (' + CAST(@NewCurrentStock AS NVARCHAR(10)) 
                          + N') thấp hơn ngưỡng tối thiểu (' + CAST(@NewMinThreshold AS NVARCHAR(10)) + N'). ';
        END

        -- Cảnh báo: Tăng giá đáng kể (>20%)
        IF @UnitPrice IS NOT NULL AND @OldUnitPrice > 0 
           AND (@UnitPrice - @OldUnitPrice) / @OldUnitPrice > 0.2
        BEGIN
            DECLARE @PriceIncreasePercent DECIMAL(5, 2) = ((@UnitPrice - @OldUnitPrice) / @OldUnitPrice) * 100;
            SET @Warnings = @Warnings + N'⚠️ Giá tăng ' + CAST(@PriceIncreasePercent AS NVARCHAR(10)) + N'%. ';
        END

        -- Cảnh báo: Giảm giá đáng kể (>20%)
        IF @UnitPrice IS NOT NULL AND @OldUnitPrice > 0 
           AND (@OldUnitPrice - @UnitPrice) / @OldUnitPrice > 0.2
        BEGIN
            DECLARE @PriceDecreasePercent DECIMAL(5, 2) = ((@OldUnitPrice - @UnitPrice) / @OldUnitPrice) * 100;
            SET @Warnings = @Warnings + N'⚠️ Giá giảm ' + CAST(@PriceDecreasePercent AS NVARCHAR(10)) + N'%. ';
        END

        -- Cảnh báo: Đặt status = Còn nhưng stock = 0
        IF @Status = N'Còn' AND @NewCurrentStock = 0
        BEGIN
            SET @Warnings = @Warnings + N'⚠️ Trạng thái "Còn" nhưng tồn kho = 0. ';
        END

        -- Cảnh báo: Đặt status = Hết nhưng stock > 0
        IF @Status = N'Hết' AND @NewCurrentStock > 0
        BEGIN
            SET @Warnings = @Warnings + N'⚠️ Trạng thái "Hết" nhưng còn ' + CAST(@NewCurrentStock AS NVARCHAR(10)) + N' trong kho. ';
        END

        -- Cảnh báo: Tồn kho sắp hết (= 0)
        IF @StockQuantity IS NOT NULL AND @NewCurrentStock = 0
        BEGIN
            SET @Warnings = @Warnings + N'⚠️ Tồn kho đã hết (0). Cân nhắc cập nhật trạng thái thành "Hết". ';
        END

        -- Trim warnings
        IF LEN(@Warnings) > 0
            SET @Warnings = LTRIM(RTRIM(@Warnings));
        ELSE
            SET @Warnings = NULL;

        /*------------------------------------------------------
         * 8. Commit và trả về kết quả
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Cập nhật dịch vụ "' + @ServiceName + N'" ở chi nhánh "' + @BranchName 
            + N'" thành công. Số trường đã cập nhật: ' + CAST(@UpdateCount AS NVARCHAR(10)) AS Message,
            @BranchServiceID AS BranchServiceID,
            @BranchName AS BranchName,
            @ServiceName AS ServiceName,
            @UpdatedFields AS UpdatedFields,
            @Warnings AS Warnings;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi cập nhật dịch vụ: ' + ERROR_MESSAGE() AS Message,
            @BranchServiceID AS BranchServiceID,
            NULL AS BranchName,
            NULL AS ServiceName,
            NULL AS UpdatedFields,
            NULL AS Warnings;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: USP_UPDATE_BRANCH_SERVICE ===';
GO

-- ====================================================================
-- Test ERR04 (dirty read) với Nước Revive (BranchServiceID = 1)
--Session T2 - Quản lý
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
BEGIN TRAN;
EXEC USP_UPDATE_BRANCH_SERVICE
    @BranchServiceID = 5,      -- Nước Revive
    @StockQuantity = -6;       -- giả sử trừ 6 đơn vị
COMMIT;


