USE SportsCenterDB;
GO

-- =============================================
-- 6. SP_GetEmployeeSalary
-- Mô tả: Xem bảng lương của nhân viên
-- Trả về 2 result sets:
--   1) Thống kê tổng quan
--   2) Lịch sử lương chi tiết (bảng) + Tổng số ca trực được tính
-- =============================================
CREATE OR ALTER PROCEDURE SP_GetEmployeeSalary
    @EmployeeId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Kiểm tra nhân viên tồn tại
    IF NOT EXISTS (SELECT 1 FROM employee WHERE id = @EmployeeId)
    BEGIN
        SELECT 
            0 AS Success,
            N'Nhân viên không tồn tại' AS Message;
        RETURN;
    END
    
    -- Lấy năm hiện tại
    DECLARE @CurrentYear INT = YEAR(GETDATE());
    
    -- Result Set 1: Thống kê tổng quan
    SELECT 
        -- Lương tháng gần nhất
        (SELECT TOP 1 net_pay 
         FROM salary_history 
         WHERE employee_id = @EmployeeId 
         ORDER BY [year] DESC, [month] DESC) AS LatestSalary,
        
        -- Tổng lương đã nhận trong năm hiện tại
        SUM(CASE 
            WHEN [year] = @CurrentYear AND payment_status = N'Đã thanh toán' 
            THEN net_pay 
            ELSE 0 
        END) AS TotalReceivedThisYear,
        
        -- Số kỳ đã trả trong năm
        SUM(CASE 
            WHEN [year] = @CurrentYear AND payment_status = N'Đã thanh toán'
            THEN 1 
            ELSE 0 
        END) AS PaidPeriodsThisYear,
        
        @CurrentYear AS [Year]
    FROM salary_history
    WHERE employee_id = @EmployeeId;
    
    -- Result Set 2: Lịch sử lương chi tiết + Tổng ca trực
    SELECT 
        [month] AS [Month],
        [year] AS [Year],
        CONCAT(N'Tháng ', [month], '/', [year]) AS MonthDisplay, -- "Tháng 7/2024"
        base_salary AS BaseSalary, -- Lương cơ bản
        base_allowance AS BaseAllowance, -- Phụ cấp
        commission_amount AS CommissionAmount, -- Hoa hồng
        deduction_penalty AS DeductionPenalty, -- Khấu trừ
        gross_pay AS GrossPay, -- Tổng thu nhập
        net_pay AS NetPay, -- Thực nhận
        payment_status AS PaymentStatus, -- Trạng thái
        payment_method AS PaymentMethod, -- Hình thức
        
        -- Tổng số ca trực được tính cho lương tháng đó
        (SELECT COUNT(*) 
         FROM shift_assignment sa
         INNER JOIN work_shift ws ON sa.work_shift_id = ws.id
         WHERE sa.employee_id = @EmployeeId
           AND sa.[status] = N'Đã chấm công'
           AND MONTH(ws.[date]) = sh.[month]
           AND YEAR(ws.[date]) = sh.[year]) AS TotalShifts
           
    FROM salary_history sh
    WHERE sh.employee_id = @EmployeeId
    ORDER BY [year] DESC, [month] DESC;
END
GO
