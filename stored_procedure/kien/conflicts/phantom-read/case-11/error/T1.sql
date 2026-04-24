USE SportsCenterDB;
GO

/* SP DEMO: Tính lương bị sai do Phantom Read */
CREATE OR ALTER PROCEDURE sp_CalculateSalary
    @Month INT,
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
        BEGIN TRANSACTION;

        -- ======================================================
        -- BƯỚC 1: SNAPSHOT (ĐỌC DỮ LIỆU ĐẦU VÀO)
        -- Đọc số ngày nghỉ và tính phạt ngay tại đây
        -- ======================================================
        DECLARE @PreCheckSalary TABLE (
            emp_id INT, 
            base_salary DECIMAL(18, 2),
            base_allowance DECIMAL(18, 2), 
            branch_id INT, 
            commission_rate DECIMAL(18,2),
            frozen_deduction DECIMAL(18, 2) 
        );

        INSERT INTO @PreCheckSalary (emp_id, base_salary, base_allowance, branch_id, commission_rate, frozen_deduction)
        SELECT 
            e.id, e.base_salary, e.base_allowance, e.branch_id, e.commission_rate,
            
            -- [SNAPSHOT]: Đếm ngày nghỉ và nhân tiền phạt NGAY LÚC NÀY
            (SELECT COUNT(*) FROM shift_assignment sa 
             JOIN work_shift ws ON sa.work_shift_id = ws.id
             WHERE sa.employee_id = e.id AND sa.status = 'Absent' 
             AND MONTH(ws.date) = @Month AND YEAR(ws.date) = @Year) 
             * (SELECT TOP 1 shift_absence_penalty FROM branch WHERE id = e.branch_id)
        FROM employee e
        WHERE NOT EXISTS (
            SELECT 1 FROM salary_history sh 
            WHERE sh.employee_id = e.id AND sh.[month] = @Month AND sh.[year] = @Year
        )
        AND e.status = N'Đang làm';

        PRINT N'1. [T1] Đã Snapshot và Tính tiền phạt (Dựa trên dữ liệu cũ).';

        -- B2: DELAY (Để T2 kịp tạo Phantom Data)
        PRINT N'2. [T1] Hệ thống đang xử lý (Delay 10s)...';
        WAITFOR DELAY '00:00:10';

        -- ======================================================
        -- BƯỚC 3: TÍNH TOÁN & GHI (DỰA TRÊN DỮ LIỆU ĐÃ SNAPSHOT)
        -- Giờ mới bắt đầu tính lương dựa trên số liệu cũ
        -- ======================================================
        INSERT INTO salary_history (
            employee_id, [year], [month], base_salary, base_allowance, commission_rate, 
            commission_amount, deduction_penalty, gross_pay, net_pay, 
            payment_status, payment_method, paid_at
        )
        SELECT 
            t.emp_id, @Year, @Month, 
            t.base_salary, 
            ISNULL(t.base_allowance, 0), ISNULL(t.commission_rate, 0),
            0 AS commission_amount,
            
            t.frozen_deduction, -- Dùng số tiền phạt ĐÃ ĐÓNG BĂNG ở B1 (Cũ)

            (t.base_salary + ISNULL(t.base_allowance, 0)) AS gross_pay,

            -- Tính Net Pay: Lương cứng - Tiền phạt (Cũ)
            -- Dù T2 có thêm 10 ngày nghỉ đi nữa, dòng này vẫn trừ theo số cũ.
            (t.base_salary + ISNULL(t.base_allowance, 0)) - t.frozen_deduction,
            
            N'Chưa thanh toán', N'Chuyển khoản', GETDATE()
        FROM @PreCheckSalary t;

        PRINT N'3. [T1] Đã ghi lương xong (Bị thiếu tiền phạt).';
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- SCRIPT GỌI HÀM
-- Reset dữ liệu test (Xóa lương cũ nếu có)
DELETE FROM salary_history WHERE [month] = 12 AND [year] = 2025;

-- Chạy Demo
EXEC sp_CalculateSalary @Month = 12, @Year = 2025;