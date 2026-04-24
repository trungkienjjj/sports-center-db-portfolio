/* ================================================================
 * TEST CASES - REACTIVATE
 * ================================================================*/
PRINT N'';
PRINT N'============================================================';
PRINT N'BẮT ĐẦU TEST USP_MANAGER_REACTIVATE_EMPLOYEE';
PRINT N'============================================================';
PRINT N'';

/* TC08: Kích hoạt lại nhân viên thành công */
PRINT N'TC08 - Kích hoạt lại nhân viên đã nghỉ việc';
BEGIN TRY
    TRUNCATE TABLE #Result2;
    INSERT INTO #Result2
    EXEC USP_MANAGER_REACTIVATE_EMPLOYEE
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeID;

    IF EXISTS(SELECT 1 FROM #Result2 WHERE Success = 1)
    BEGIN
        -- Verify trong DB
        SELECT @DBStatus = e.[status], @DBActive = a.is_active
        FROM employee e
        JOIN account a ON e.user_id = a.id
        WHERE e.id = @TestEmployeeID;

        IF @DBStatus = N'Đang làm' AND @DBActive = 1
            PRINT N'  => PASS (Status: Đang làm, Account: Active)';
        ELSE
            PRINT N'  => FAIL (DB không cập nhật đúng)';
    END
    ELSE BEGIN SELECT * FROM #Result2; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC09: Kích hoạt nhân viên đang làm (reject) */
PRINT N'TC09 - Kích hoạt nhân viên đang làm (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result2;
    INSERT INTO #Result2
    EXEC USP_MANAGER_REACTIVATE_EMPLOYEE
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployeeID;

    IF EXISTS(SELECT 1 FROM #Result2 WHERE Success = 0 AND Message LIKE N'%đã nghỉ việc%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result2; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

/* TC10: Kích hoạt nhân viên chi nhánh khác (reject) */
PRINT N'TC10 - Manager HCM cố kích hoạt nhân viên chi nhánh CT (reject)';
BEGIN TRY
    TRUNCATE TABLE #Result2;
    INSERT INTO #Result2
    EXEC USP_MANAGER_REACTIVATE_EMPLOYEE
        @ManagerUserID = @ManagerHCM_UserID,
        @EmployeeID = @TestEmployee2ID;  -- Nhân viên CT

    IF EXISTS(SELECT 1 FROM #Result2 WHERE Success = 0 AND Message LIKE N'%chi nhánh của mình%')
        PRINT N'  => PASS';
    ELSE BEGIN SELECT * FROM #Result2; PRINT N'  => FAIL'; END
END TRY BEGIN CATCH PRINT N'  => FAIL - ' + ERROR_MESSAGE(); END CATCH
PRINT N'------------------------------------------------------------';

PRINT N'';
PRINT N'============================================================';
PRINT N'TOÀN BỘ 10 TEST CASE ĐÃ CHẠY XONG!';
PRINT N'============================================================';

/* ================================================================
 * CLEANUP
 * ================================================================*/
PRINT N'';
PRINT N'=== CLEANUP ===';
DELETE FROM employee WHERE id IN (@TestEmployeeID, @TestEmployee2ID);
DELETE FROM account WHERE username LIKE 'test.deactivate%';
DROP TABLE #Result;
DROP TABLE #Result2;
PRINT N'=== HOÀN TẤT ===';
GO