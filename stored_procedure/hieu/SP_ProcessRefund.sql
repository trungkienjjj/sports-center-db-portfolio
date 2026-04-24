USE SportsCenterDB;
GO

-- =============================================
-- 7. SP_ProcessRefund
-- Mô tả: Thu ngân xử lý hoàn tiền
-- =============================================
CREATE OR ALTER PROCEDURE SP_ProcessRefund
    @InvoiceId INT,
    @RefundAmount DECIMAL(10, 2),
    @Reason NVARCHAR(500),
    @RefundType NVARCHAR(50),
    @RefundMethod NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    
    BEGIN TRY
        -- Kiểm tra hóa đơn tồn tại
        IF NOT EXISTS (SELECT 1 FROM invoice WHERE id = @InvoiceId)
        BEGIN
            SELECT 
                0 AS Success,
                N'Hóa đơn không tồn tại' AS Message;
            ROLLBACK TRANSACTION;
            RETURN;
        END
        
        -- Tạo thông tin hoàn tiền
        INSERT INTO refund_info (
            amount,
            reason,
            [type],
            [method],
            [status],
            created_at,
            invoice_id
        )
        VALUES (
            @RefundAmount,
            @Reason,
            @RefundType,
            @RefundMethod,
            N'Chờ xử lý',
            GETDATE(),
            @InvoiceId
        );
        
        DECLARE @RefundId INT = SCOPE_IDENTITY();
        
        -- Cập nhật trạng thái đã xử lý
        UPDATE refund_info
        SET 
            [status] = N'Đã xử lý',
            processed_at = GETDATE()
        WHERE id = @RefundId;
        
        COMMIT TRANSACTION;
        
        SELECT 
            1 AS Success,
            N'Hoàn tiền đã được xử lý thành công' AS Message,
            @RefundId AS RefundId;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        
        SELECT 
            0 AS Success,
            N'Lỗi: ' + ERROR_MESSAGE() AS Message;
    END CATCH
END
GO
