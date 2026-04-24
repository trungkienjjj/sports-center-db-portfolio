USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_update_branch_service (StockQuantity Version)
 * Người thực hiện : Bạn
 * Ngày cập nhật   : 10/12/2025
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * CHUẨN BỊ DỮ LIỆU
 * ================================================================*/
PRINT N'=== PREPARE ===';

DECLARE @BranchHCM_ID INT;
DECLARE @ServiceCoach_ID INT;
DECLARE @TestBranchServiceID INT;

-- Lấy dữ liệu mẫu
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @ServiceCoach_ID = id FROM [service] WHERE [name] = N'Huấn Luyện Viên Cá Nhân';

-- Xóa và tạo mới dịch vụ test
DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchHCM_ID 
AND bs.service_id = @ServiceCoach_ID
AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

INSERT INTO branch_service (unit_price, current_stock, min_stock_threshold, [status], branch_id, service_id)
VALUES (350000, 10, 5, N'Còn', @BranchHCM_ID, @ServiceCoach_ID);

SET @TestBranchServiceID = SCOPE_IDENTITY();

PRINT N'  -> Test Branch Service ID: ' + CAST(@TestBranchServiceID AS NVARCHAR(10));
PRINT N'  -> Giá trị ban đầu: Price=350,000, Stock=10, MinStock=5, Status=Còn';
PRINT N'';

/* ================================================================
 * TEMP TABLE
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;
CREATE TABLE #Result (
    Success           BIT,
    Message           NVARCHAR(500),
    BranchServiceID   INT,
    BranchName        NVARCHAR(255),
    ServiceName       NVARCHAR(255),
    UpdatedFields     NVARCHAR(MAX),
    Warnings          NVARCHAR(MAX)
);

/* ================================================================
 * TEST CASES
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST sp_update_branch_service (StockQuantity Version)';
PRINT N'============================================================';
PRINT N'';

/* TC01: Cập nhật 1 trường (UnitPrice) */
PRINT N'TC01 - Cập nhật đơn giá';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @UnitPrice = 400000;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND UpdatedFields LIKE '%UnitPrice%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Tăng tồn kho (+) */
PRINT N'TC02 - Tăng tồn kho thêm 20 đơn vị (Stock: 10 → 30)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = 20;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%CurrentStock%'
        AND UpdatedFields LIKE '%+20%'
    )
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Giảm tồn kho (-) */
PRINT N'TC03 - Giảm tồn kho đi 15 đơn vị (Stock: 30 → 15)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = -15;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%CurrentStock%'
        AND UpdatedFields LIKE '%-15%'
    )
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Cập nhật nhiều trường cùng lúc (StockQuantity + MinStock + Status) */
PRINT N'TC04 - Cập nhật nhiều trường (StockQuantity +10, MinStock=8, Status=Còn)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = 10,
        @MinStockThreshold = 8,
        @Status = N'Còn';

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%CurrentStock%'
        AND UpdatedFields LIKE '%MinStockThreshold%'
    )
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Tăng giá >20% (có cảnh báo) */
PRINT N'TC05 - Tăng giá >20% (có cảnh báo tăng giá)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @UnitPrice = 500000;  -- Tăng từ 400k lên 500k = 25%

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%Giá tăng%')
        PRINT N'  => PASS (Có cảnh báo tăng giá)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Giảm giá >20% (có cảnh báo) */
PRINT N'TC06 - Giảm giá >20% (có cảnh báo giảm giá)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @UnitPrice = 300000;  -- Giảm từ 500k xuống 300k = 40%

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%Giá giảm%')
        PRINT N'  => PASS (Có cảnh báo giảm giá)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: Giảm tồn kho xuống dưới ngưỡng (có cảnh báo) */
PRINT N'TC07 - Giảm tồn kho xuống dưới ngưỡng (Stock < MinStock)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = -20;  -- Giảm từ 25 xuống 5, dưới ngưỡng 8

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%thấp hơn ngưỡng%')
        PRINT N'  => PASS (Có cảnh báo tồn kho thấp)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Giảm tồn kho xuống 0 (có cảnh báo) */
PRINT N'TC08 - Giảm tồn kho xuống 0 (có cảnh báo tồn kho hết)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = -5;  -- Giảm từ 5 xuống 0

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%Tồn kho đã hết%')
        PRINT N'  => PASS (Có cảnh báo tồn kho = 0)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Status = Còn nhưng Stock = 0 (có cảnh báo) */
PRINT N'TC09 - Status = Còn nhưng Stock = 0 (có cảnh báo mâu thuẫn)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @Status = N'Còn';  -- Stock đang = 0

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%Còn%tồn kho = 0%')
        PRINT N'  => PASS (Có cảnh báo mâu thuẫn)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Tăng stock lên rồi đặt Status = Hết (có cảnh báo) */
PRINT N'TC10 - Status = Hết nhưng Stock > 0 (có cảnh báo mâu thuẫn)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = 15,
        @Status = N'Hết';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Warnings LIKE N'%Hết%còn%trong kho%')
        PRINT N'  => PASS (Có cảnh báo mâu thuẫn)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC11: Giảm tồn kho quá mức (tồn kho sẽ âm) - PHẢI FAIL */
PRINT N'TC11 - Giảm tồn kho quá mức (Stock sẽ âm) - PHẢI FAIL';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = -100;  -- Giảm quá mức

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Không thể giảm tồn kho%')
        PRINT N'  => PASS (Báo lỗi đúng)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC12: BranchServiceID không tồn tại */
PRINT N'TC12 - BranchServiceID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = 99999,
        @UnitPrice = 100000;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC13: Đơn giá âm */
PRINT N'TC13 - Đơn giá âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @UnitPrice = -50000;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Đơn giá%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC14: Ngưỡng tồn kho âm */
PRINT N'TC14 - Ngưỡng tồn kho âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @MinStockThreshold = -5;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Ngưỡng tồn kho%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC15: Trạng thái không hợp lệ */
PRINT N'TC15 - Trạng thái không hợp lệ';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @Status = N'Đang bảo trì';

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Trạng thái%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC16: Không truyền tham số nào */
PRINT N'TC16 - Không truyền tham số nào';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Không có trường nào%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC17: Cập nhật tất cả trường */
PRINT N'TC17 - Cập nhật tất cả trường cùng lúc';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @UnitPrice = 380000,
        @StockQuantity = 25,
        @MinStockThreshold = 10,
        @Status = N'Còn';

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%UnitPrice%'
        AND UpdatedFields LIKE '%CurrentStock%'
        AND UpdatedFields LIKE '%MinStockThreshold%'
        AND UpdatedFields LIKE '%Status%'
    )
        PRINT N'  => PASS (Cập nhật 4 trường)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC18: Tăng tồn kho lớn (test hiển thị +) */
PRINT N'TC18 - Tăng tồn kho lớn (+500)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = 500;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%+500%'
    )
        PRINT N'  => PASS (Hiển thị đúng dấu +)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC19: Giảm nhỏ (-1) */
PRINT N'TC19 - Giảm tồn kho nhỏ (-1)';
BEGIN TRY
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = -1;

    IF EXISTS(
        SELECT 1 FROM #Result WHERE Success = 1 
        AND UpdatedFields LIKE '%-1%'
    )
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC20: Cập nhật với StockQuantity = 0 (không thay đổi gì) */
PRINT N'TC20 - StockQuantity = 0 (không thay đổi stock)';
BEGIN TRY
    -- Lấy stock hiện tại
    DECLARE @CurrentStockBefore INT;
    SELECT @CurrentStockBefore = current_stock FROM branch_service WHERE id = @TestBranchServiceID;
    
    TRUNCATE TABLE #Result;
    INSERT INTO #Result
    EXEC sp_update_branch_service
        @BranchServiceID = @TestBranchServiceID,
        @StockQuantity = 0;

    DECLARE @CurrentStockAfter INT;
    SELECT @CurrentStockAfter = current_stock FROM branch_service WHERE id = @TestBranchServiceID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1) AND @CurrentStockBefore = @CurrentStockAfter
        PRINT N'  => PASS (Stock không đổi)';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 20 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';

DELETE bs
FROM branch_service bs
WHERE bs.id = @TestBranchServiceID
AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

DROP TABLE #Result;
PRINT N'=== HOÀN TẤT ===';
GO