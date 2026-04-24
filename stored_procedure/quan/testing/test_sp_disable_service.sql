USE SportsCenterDB;
GO

/*
 * =================================================================
 * TEST SCRIPT - USP_DISABLE_BRANCH_SERVICE
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
DECLARE @ServiceCoach_ID INT;
DECLARE @TestBranchServiceID INT;

-- Lấy dữ liệu mẫu
SELECT @BranchHCM_ID = id FROM branch WHERE [name] = N'VietSport TP.HCM';
SELECT @ServiceCoach_ID = id FROM [service] WHERE [name] = N'Huấn Luyện Viên Cá Nhân';

-- Tạo dịch vụ test để vô hiệu hóa
-- Xóa nếu đã tồn tại (không có FK)
DELETE bs
FROM branch_service bs
WHERE bs.branch_id = @BranchHCM_ID 
AND bs.service_id = @ServiceCoach_ID
AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

-- Thêm dịch vụ mới để test
INSERT INTO branch_service (unit_price, current_stock, min_stock_threshold, [status], branch_id, service_id)
VALUES (350000, 5, 2, N'Còn', @BranchHCM_ID, @ServiceCoach_ID);

SET @TestBranchServiceID = SCOPE_IDENTITY();

PRINT N'  -> Đã tạo Branch Service ID: ' + CAST(@TestBranchServiceID AS NVARCHAR(10));
PRINT N'  -> Trạng thái ban đầu: Còn (Stock: 5)';
PRINT N'';

/* ================================================================
 * TEMP TABLE
 * ================================================================*/
IF OBJECT_ID('tempdb..#Result') IS NOT NULL DROP TABLE #Result;
CREATE TABLE #Result (
    Success BIT,
    Message NVARCHAR(500)
);

/* ================================================================
 * TEST CASES
 * ================================================================*/
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST USP_DISABLE_BRANCH_SERVICE';
PRINT N'============================================================';
PRINT N'';

/* TC01: Vô hiệu hóa dịch vụ thành công */
PRINT N'TC01 - Vô hiệu hóa dịch vụ thành công';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_disable_branch_service @BranchServiceID = @TestBranchServiceID;

    -- Kiểm tra kết quả trả về
    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1)
    BEGIN
        -- Kiểm tra status và stock trong DB
        DECLARE @NewStatus NVARCHAR(50);
        DECLARE @NewStock INT;
        
        SELECT @NewStatus = [status], @NewStock = current_stock
        FROM branch_service
        WHERE id = @TestBranchServiceID;

        IF @NewStatus = N'Hết' AND @NewStock = 0
            PRINT N'  => PASS (Status: Hết, Stock: 0)';
        ELSE
            PRINT N'  => FAIL (Status: ' + ISNULL(@NewStatus, 'NULL') + N', Stock: ' + CAST(@NewStock AS NVARCHAR(10)) + N')';
    END
    ELSE
    BEGIN
        SELECT * FROM #Result;
        PRINT N'  => FAIL';
    END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC02: Vô hiệu hóa dịch vụ đã bị vô hiệu hóa rồi */
PRINT N'TC02 - Vô hiệu hóa dịch vụ đã ở trạng thái Hết';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_disable_branch_service @BranchServiceID = @TestBranchServiceID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%đã ở trạng thái%Hết%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #Result;
        PRINT N'  => FAIL';
    END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC03: BranchServiceID không tồn tại */
PRINT N'TC03 - BranchServiceID không tồn tại';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_disable_branch_service @BranchServiceID = 99999;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không tồn tại%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #Result;
        PRINT N'  => FAIL';
    END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC04: BranchServiceID NULL */
PRINT N'TC04 - BranchServiceID NULL';
BEGIN TRY
    TRUNCATE TABLE #Result;
    EXEC sp_disable_branch_service @BranchServiceID = NULL;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 0 AND Message LIKE N'%không được để trống%')
        PRINT N'  => PASS';
    ELSE
    BEGIN
        SELECT * FROM #Result;
        PRINT N'  => FAIL';
    END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC05: Kích hoạt lại và vô hiệu hóa lần nữa */
PRINT N'TC05 - Kích hoạt lại rồi vô hiệu hóa lần 2';
BEGIN TRY
    -- Kích hoạt lại
    UPDATE branch_service
    SET [status] = N'Còn', current_stock = 10
    WHERE id = @TestBranchServiceID;

    PRINT N'  -> Đã kích hoạt lại (Status: Còn, Stock: 10)';

    -- Vô hiệu hóa lần 2
    TRUNCATE TABLE #Result;
    EXEC sp_disable_branch_service @BranchServiceID = @TestBranchServiceID;

    IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1)
    BEGIN
        DECLARE @Status2 NVARCHAR(50);
        DECLARE @Stock2 INT;
        
        SELECT @Status2 = [status], @Stock2 = current_stock
        FROM branch_service
        WHERE id = @TestBranchServiceID;

        IF @Status2 = N'Hết' AND @Stock2 = 0
            PRINT N'  => PASS (Vô hiệu hóa lần 2 thành công)';
        ELSE
            PRINT N'  => FAIL';
    END
    ELSE
    BEGIN
        SELECT * FROM #Result;
        PRINT N'  => FAIL';
    END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC06: Test với dịch vụ đã có booking (từ dữ liệu mẫu) */
PRINT N'TC06 - Vô hiệu hóa dịch vụ đã có booking';
BEGIN TRY
    -- Lấy branch_service có booking từ dữ liệu mẫu
    DECLARE @ExistingBSID INT;
    
    SELECT TOP 1 @ExistingBSID = bs.id
    FROM branch_service bs
    JOIN service_booking_item sbi ON sbi.branch_service_id = bs.id
    WHERE bs.[status] = N'Còn';

    IF @ExistingBSID IS NOT NULL
    BEGIN
        TRUNCATE TABLE #Result;
        EXEC sp_disable_branch_service @BranchServiceID = @ExistingBSID;

        IF EXISTS(SELECT 1 FROM #Result WHERE Success = 1)
            PRINT N'  => PASS (Có thể vô hiệu hóa dù có booking)';
        ELSE
        BEGIN
            SELECT * FROM #Result;
            PRINT N'  => FAIL';
        END

        -- Khôi phục lại trạng thái cũ
        UPDATE branch_service
        SET [status] = N'Còn'
        WHERE id = @ExistingBSID;
    END
    ELSE
        PRINT N'  => SKIP (Không có dịch vụ có booking để test)';
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 6 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';

-- Xóa dịch vụ test (nếu không có FK)
DELETE bs
FROM branch_service bs
WHERE bs.id = @TestBranchServiceID
AND NOT EXISTS(SELECT 1 FROM service_booking_item WHERE branch_service_id = bs.id);

DROP TABLE #Result;
PRINT N'=== HOÀN TẤT ===';
GO