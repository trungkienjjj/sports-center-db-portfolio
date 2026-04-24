USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - sp_add_branch_service
 * Người thực hiện : Bạn
 * Ngày            : 07/12/2025
 * =================================================================
 */

SET NOCOUNT ON;

/* ================================================================
 * CHUẨN BỊ DỮ LIỆU
 * ================================================================*/
PRINT N'=== PREPARE ===';

DECLARE @BranchHCM_ID INT;
DECLARE @BranchCT_ID INT;
DECLARE @ServiceBall_ID INT;
DECLARE @ServiceLocker_ID INT;
DECLARE @ServiceRevive_ID INT;
DECLARE @ServiceCoach_ID INT;

-- Lấy dữ liệu mẫu
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @BranchCT_ID = id FROM branch WHERE [name] = N'VietSport Cần Thơ';
SELECT @ServiceBall_ID = id FROM [service] WHERE [name] = N'Thuê Bóng Đá';
SELECT @ServiceLocker_ID = id FROM [service] WHERE [name] = N'Tủ Đồ Cá Nhân';
SELECT @ServiceRevive_ID = id FROM [service] WHERE [name] = N'Nước Revive';
SELECT @ServiceCoach_ID = id FROM [service] WHERE [name] = N'Huấn Luyện Viên Cá Nhân';

-- Xóa dịch vụ test cũ (CHỈ nếu không có FK)
DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchHCM_ID 
AND bs.service_id IN (@ServiceCoach_ID)
AND NOT EXISTS(
    SELECT 1 FROM service_booking_item sbi 
    WHERE sbi.branch_service_id = bs.id
);

DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchCT_ID 
AND bs.service_id IN (@ServiceRevive_ID)
AND NOT EXISTS(
    SELECT 1 FROM service_booking_item sbi 
    WHERE sbi.branch_service_id = bs.id
);

PRINT N'  -> Branch HCM: ' + CAST(@BranchHCM_ID AS NVARCHAR(10));
PRINT N'  -> Branch CT: ' + CAST(@BranchCT_ID AS NVARCHAR(10));
PRINT N'  -> Service Coach: ' + CAST(@ServiceCoach_ID AS NVARCHAR(10));
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
    Status            NVARCHAR(50)
);

/* ================================================================
 * TEST CASES
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST';
PRINT N'============================================================';
PRINT N'';

/* TC01: Thêm dịch vụ thành công (stock > 0 → Còn) */
PRINT N'TC01 - Thêm dịch vụ thành công (Trạng thái: Còn)';
BEGIN TRY
    -- Xóa nếu tồn tại và không có FK
    DELETE bs
    FROM branch_service bs
    WHERE bs.branch_id = @BranchHCM_ID AND bs.service_id = @ServiceCoach_ID
    AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = @ServiceCoach_ID,
        @UnitPrice = 350000,
        @CurrentStock = 5,
        @MinStockThreshold = 2;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Status = N'Còn')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Thêm dịch vụ với stock = 0 → Hết */
PRINT N'TC02 - Thêm dịch vụ với tồn kho = 0 (Trạng thái: Hết)';
BEGIN TRY
    -- Xóa nếu tồn tại và không có FK
    DELETE bs
    FROM branch_service bs
    WHERE bs.branch_id = @BranchCT_ID AND bs.service_id = @ServiceRevive_ID
    AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchCT_ID,
        @ServiceID = @ServiceRevive_ID,
        @UnitPrice = 20000,
        @CurrentStock = 0,
        @MinStockThreshold = 10;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1 AND Status = N'Hết')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: Dịch vụ đã tồn tại */
PRINT N'TC03 - Dịch vụ đã tồn tại ở chi nhánh';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = @ServiceCoach_ID,  -- Đã thêm ở TC01
        @UnitPrice = 400000,
        @CurrentStock = 10,
        @MinStockThreshold = 3;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%đã tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: Chi nhánh không tồn tại */
PRINT N'TC04 - Chi nhánh không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = 99999,
        @ServiceID = @ServiceBall_ID,
        @UnitPrice = 20000,
        @CurrentStock = 50,
        @MinStockThreshold = 10;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Chi nhánh không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Dịch vụ không tồn tại */
PRINT N'TC05 - Dịch vụ không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = 99999,
        @UnitPrice = 20000,
        @CurrentStock = 50,
        @MinStockThreshold = 10;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Dịch vụ không tồn tại%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Đơn giá âm */
PRINT N'TC06 - Đơn giá âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = @ServiceBall_ID,
        @UnitPrice = -5000,
        @CurrentStock = 50,
        @MinStockThreshold = 10;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Đơn giá%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC07: Tồn kho âm */
PRINT N'TC07 - Tồn kho âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = @ServiceBall_ID,
        @UnitPrice = 20000,
        @CurrentStock = -10,
        @MinStockThreshold = 10;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Tồn kho%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC08: Ngưỡng tồn kho âm */
PRINT N'TC08 - Ngưỡng tồn kho âm';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_add_branch_service
        @BranchID = @BranchHCM_ID,
        @ServiceID = @ServiceBall_ID,
        @UnitPrice = 20000,
        @CurrentStock = 50,
        @MinStockThreshold = -5;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%Ngưỡng tồn kho%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 8 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';

-- Chỉ xóa nếu không có FK
DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchHCM_ID 
AND bs.service_id = @ServiceCoach_ID
AND NOT EXISTS(
    SELECT 1 FROM service_booking_item sbi 
    WHERE sbi.branch_service_id = bs.id
);

DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchCT_ID 
AND bs.service_id = @ServiceRevive_ID
AND NOT EXISTS(
    SELECT 1 FROM service_booking_item sbi 
    WHERE sbi.branch_service_id = bs.id
);

DROP TABLE #Result;
PRINT N'=== HOÀN TẤT ===';
GO