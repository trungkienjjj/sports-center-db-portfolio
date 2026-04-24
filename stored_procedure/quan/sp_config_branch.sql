USE SportsCenterDB;
GO

/*
 * =================================================================================
 * STORED PROCEDURE - MANAGER CẤU HÌNH THAM SỐ CHI NHÁNH
 * =================================================================================
 */

/*
 * Manager cấu hình tham số cho chi nhánh của mình (sp_config_branch)
 * 
 * Chức năng:
 *   - Manager cập nhật các tham số hoạt động của chi nhánh
 *   - Chỉ được cập nhật chi nhánh của mình
 *   - Kiểm tra giá trị hợp lệ (không âm, phần trăm 0-1)
 *   - Ghi nhận các tham số đã thay đổi
 *   - Cảnh báo nếu thay đổi quan trọng (phí hủy, phụ thu...)
 *
 * Tham số đầu vào:
 *   @ManagerUserID            uniqueidentifier : ID Manager (kiểm tra quyền)
 *   @LateTimeLimit            INT = NULL : Giới hạn phút trễ
 *   @MaxCourtsPerUser         INT = NULL : Số sân tối đa/ngày/user
 *   @ShiftPay                 DECIMAL(10,2) = NULL : Lương ca trực
 *   @ShiftAbsencePenalty      DECIMAL(10,2) = NULL : Phạt vắng ca
 *   @LoyaltyPointRate         DECIMAL(5,2) = NULL : Tỷ lệ tích điểm (0-1)
 *   @CancelFeeBefore24h       DECIMAL(5,2) = NULL : Phí hủy trước 24h (0-1)
 *   @CancelFeeWithin24h       DECIMAL(5,2) = NULL : Phí hủy trong 24h (0-1)
 *   @NoShowFee                DECIMAL(5,2) = NULL : Phí không đến (0-1)
 *   @NightCharge              DECIMAL(10,2) = NULL : Phụ thu giờ tối (0-1)
 *   @HolidayCharge            DECIMAL(10,2) = NULL : Phụ thu ngày lễ (0-1)
 *   @WeekendCharge            DECIMAL(10,2) = NULL : Phụ thu cuối tuần (0-1)
 *
 * Kết quả trả về:
 *   Success, Message, BranchID, BranchName, UpdatedFields, Warnings
 *
 * Ví dụ:
 *   EXEC sp_config_branch
 *       @ManagerUserID = 'GUID-MANAGER',
 *       @ShiftPay = 120000,
 *       @CancelFeeWithin24h = 0.60;
 * ====================================================================
 */
CREATE OR ALTER PROCEDURE sp_config_branch
    @ManagerUserID            uniqueidentifier,
    @LateTimeLimit            INT = NULL,
    @MaxCourtsPerUser         INT = NULL,
    @ShiftPay                 DECIMAL(10, 2) = NULL,
    @ShiftAbsencePenalty      DECIMAL(10, 2) = NULL,
    @LoyaltyPointRate         DECIMAL(5, 2) = NULL,
    @CancelFeeBefore24h       DECIMAL(5, 2) = NULL,
    @CancelFeeWithin24h       DECIMAL(5, 2) = NULL,
    @NoShowFee                DECIMAL(5, 2) = NULL,
    @NightCharge              DECIMAL(10, 2) = NULL,
    @HolidayCharge            DECIMAL(10, 2) = NULL,
    @WeekendCharge            DECIMAL(10, 2) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @ManagerBranchID    INT,
        @BranchName         NVARCHAR(255),
        @UpdatedFields      NVARCHAR(MAX) = N'',
        @Warnings           NVARCHAR(MAX) = N'',
        @UpdateCount        INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        /*------------------------------------------------------
         * 1. Kiểm tra Manager tồn tại và lấy BranchID
         *-----------------------------------------------------*/
        IF @ManagerUserID IS NULL
        BEGIN
            SELECT 0 AS Success, N'ID Manager không được để trống.' AS Message,
                   NULL AS BranchID, NULL AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        SELECT @ManagerBranchID = e.branch_id
        FROM employee e
        JOIN account a ON e.user_id = a.id
        JOIN [role] r ON a.role_id = r.id
        WHERE a.id = @ManagerUserID AND r.[name] = N'Quản lý';

        IF @ManagerBranchID IS NULL
        BEGIN
            SELECT 0 AS Success, N'Manager không tồn tại hoặc không có quyền Quản lý.' AS Message,
                   NULL AS BranchID, NULL AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Lấy tên chi nhánh
        SELECT @BranchName = [name] FROM branch WHERE id = @ManagerBranchID;

        /*------------------------------------------------------
         * 2. Kiểm tra có tham số nào được cập nhật không
         *-----------------------------------------------------*/
        IF @LateTimeLimit IS NULL AND @MaxCourtsPerUser IS NULL AND @ShiftPay IS NULL 
           AND @ShiftAbsencePenalty IS NULL AND @LoyaltyPointRate IS NULL 
           AND @CancelFeeBefore24h IS NULL AND @CancelFeeWithin24h IS NULL 
           AND @NoShowFee IS NULL AND @NightCharge IS NULL 
           AND @HolidayCharge IS NULL AND @WeekendCharge IS NULL
        BEGIN
            SELECT 0 AS Success, N'Không có tham số nào được cập nhật.' AS Message,
                   @ManagerBranchID AS BranchID, @BranchName AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 3. Kiểm tra giá trị hợp lệ
         *-----------------------------------------------------*/
        -- Kiểm tra không âm
        IF (@LateTimeLimit IS NOT NULL AND @LateTimeLimit < 0)
           OR (@MaxCourtsPerUser IS NOT NULL AND @MaxCourtsPerUser < 0)
           OR (@ShiftPay IS NOT NULL AND @ShiftPay < 0)
           OR (@ShiftAbsencePenalty IS NOT NULL AND @ShiftAbsencePenalty < 0)
        BEGIN
            SELECT 0 AS Success, N'Giá trị thời gian, số lượng, tiền phải >= 0.' AS Message,
                   @ManagerBranchID AS BranchID, @BranchName AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra phần trăm (0-1)
        IF (@LoyaltyPointRate IS NOT NULL AND (@LoyaltyPointRate < 0 OR @LoyaltyPointRate > 1))
           OR (@CancelFeeBefore24h IS NOT NULL AND (@CancelFeeBefore24h < 0 OR @CancelFeeBefore24h > 1))
           OR (@CancelFeeWithin24h IS NOT NULL AND (@CancelFeeWithin24h < 0 OR @CancelFeeWithin24h > 1))
           OR (@NoShowFee IS NOT NULL AND (@NoShowFee < 0 OR @NoShowFee > 1))
           OR (@NightCharge IS NOT NULL AND (@NightCharge < 0 OR @NightCharge > 1))
           OR (@HolidayCharge IS NOT NULL AND (@HolidayCharge < 0 OR @HolidayCharge > 1))
           OR (@WeekendCharge IS NOT NULL AND (@WeekendCharge < 0 OR @WeekendCharge > 1))
        BEGIN
            SELECT 0 AS Success, N'Tỷ lệ phần trăm phải nằm trong khoảng 0-1 (0% - 100%).' AS Message,
                   @ManagerBranchID AS BranchID, @BranchName AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- Kiểm tra logic: phí hủy trong 24h phải >= phí hủy trước 24h
        IF @CancelFeeWithin24h IS NOT NULL AND @CancelFeeBefore24h IS NOT NULL
           AND @CancelFeeWithin24h < @CancelFeeBefore24h
        BEGIN
            SELECT 0 AS Success, N'Phí hủy trong 24h phải >= phí hủy trước 24h.' AS Message,
                   @ManagerBranchID AS BranchID, @BranchName AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
            ROLLBACK TRANSACTION;
            RETURN;
        END

        /*------------------------------------------------------
         * 4. Cập nhật dữ liệu
         *-----------------------------------------------------*/
        UPDATE branch
        SET
            late_time_limit = CASE WHEN @LateTimeLimit IS NOT NULL THEN @LateTimeLimit ELSE late_time_limit END,
            max_courts_per_day_per_user = CASE WHEN @MaxCourtsPerUser IS NOT NULL THEN @MaxCourtsPerUser ELSE max_courts_per_day_per_user END,
            shift_pay = CASE WHEN @ShiftPay IS NOT NULL THEN @ShiftPay ELSE shift_pay END,
            shift_absence_penalty = CASE WHEN @ShiftAbsencePenalty IS NOT NULL THEN @ShiftAbsencePenalty ELSE shift_absence_penalty END,
            loyalty_point_rate = CASE WHEN @LoyaltyPointRate IS NOT NULL THEN @LoyaltyPointRate ELSE loyalty_point_rate END,
            cancel_fee_before_24h_percent = CASE WHEN @CancelFeeBefore24h IS NOT NULL THEN @CancelFeeBefore24h ELSE cancel_fee_before_24h_percent END,
            cancel_fee_within_24h_percent = CASE WHEN @CancelFeeWithin24h IS NOT NULL THEN @CancelFeeWithin24h ELSE cancel_fee_within_24h_percent END,
            no_show_fee_percent = CASE WHEN @NoShowFee IS NOT NULL THEN @NoShowFee ELSE no_show_fee_percent END,
            night_booking_additional_charge = CASE WHEN @NightCharge IS NOT NULL THEN @NightCharge ELSE night_booking_additional_charge END,
            holiday_booking_additional_charge = CASE WHEN @HolidayCharge IS NOT NULL THEN @HolidayCharge ELSE holiday_booking_additional_charge END,
            weekend_booking_additional_charge = CASE WHEN @WeekendCharge IS NOT NULL THEN @WeekendCharge ELSE weekend_booking_additional_charge END
        WHERE id = @ManagerBranchID;

        /*------------------------------------------------------
         * 5. Ghi nhận các trường đã cập nhật
         *-----------------------------------------------------*/
        IF @LateTimeLimit IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'LateTimeLimit, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @MaxCourtsPerUser IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'MaxCourtsPerUser, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @ShiftPay IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'ShiftPay, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @ShiftAbsencePenalty IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'ShiftAbsencePenalty, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @LoyaltyPointRate IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'LoyaltyPointRate, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @CancelFeeBefore24h IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'CancelFeeBefore24h, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @CancelFeeWithin24h IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'CancelFeeWithin24h, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @NoShowFee IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'NoShowFee, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @NightCharge IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'NightCharge, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @HolidayCharge IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'HolidayCharge, '; SET @UpdateCount = @UpdateCount + 1; END
        IF @WeekendCharge IS NOT NULL BEGIN SET @UpdatedFields = @UpdatedFields + N'WeekendCharge, '; SET @UpdateCount = @UpdateCount + 1; END

        -- Bỏ dấu phẩy cuối
        IF LEN(@UpdatedFields) > 0
            SET @UpdatedFields = LEFT(@UpdatedFields, LEN(@UpdatedFields) - 2);

        /*------------------------------------------------------
         * 6. Tạo cảnh báo
         *-----------------------------------------------------*/
        -- Cảnh báo tăng phí hủy
        IF @CancelFeeWithin24h IS NOT NULL AND @CancelFeeWithin24h > 0.5
            SET @Warnings = @Warnings + N'⚠️ Phí hủy trong 24h cao (' + CAST(@CancelFeeWithin24h * 100 AS NVARCHAR(10)) + N'%). ';

        -- Cảnh báo tăng phụ thu
        IF @NightCharge IS NOT NULL AND @NightCharge > 0.2
            SET @Warnings = @Warnings + N'⚠️ Phụ thu giờ tối cao (' + CAST(@NightCharge * 100 AS NVARCHAR(10)) + N'%). ';

        IF @HolidayCharge IS NOT NULL AND @HolidayCharge > 0.3
            SET @Warnings = @Warnings + N'⚠️ Phụ thu ngày lễ cao (' + CAST(@HolidayCharge * 100 AS NVARCHAR(10)) + N'%). ';

        -- Cảnh báo giảm lương ca
        IF @ShiftPay IS NOT NULL AND @ShiftPay < 80000
            SET @Warnings = @Warnings + N'⚠️ Lương ca thấp (' + FORMAT(@ShiftPay, 'N0') + N' VNĐ). ';

        -- Cảnh báo giới hạn sân quá ít
        IF @MaxCourtsPerUser IS NOT NULL AND @MaxCourtsPerUser < 2
            SET @Warnings = @Warnings + N'⚠️ Giới hạn sân quá ít (' + CAST(@MaxCourtsPerUser AS NVARCHAR(10)) + N' sân/ngày). ';

        -- Trim warnings
        IF LEN(@Warnings) > 0
            SET @Warnings = LTRIM(RTRIM(@Warnings));
        ELSE
            SET @Warnings = NULL;

        /*------------------------------------------------------
         * 7. Commit và trả về kết quả
         *-----------------------------------------------------*/
        COMMIT TRANSACTION;

        SELECT 
            1 AS Success,
            N'Cập nhật cấu hình chi nhánh "' + @BranchName + N'" thành công. Số tham số cập nhật: ' 
            + CAST(@UpdateCount AS NVARCHAR(10)) AS Message,
            @ManagerBranchID AS BranchID,
            @BranchName AS BranchName,
            @UpdatedFields AS UpdatedFields,
            @Warnings AS Warnings;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        SELECT 
            0 AS Success,
            N'Lỗi khi cập nhật cấu hình: ' + ERROR_MESSAGE() AS Message,
            NULL AS BranchID, NULL AS BranchName, NULL AS UpdatedFields, NULL AS Warnings;
    END CATCH
END;
GO

PRINT N'=== ĐÃ TẠO STORED PROCEDURE: sp_config_branch ===';
GO