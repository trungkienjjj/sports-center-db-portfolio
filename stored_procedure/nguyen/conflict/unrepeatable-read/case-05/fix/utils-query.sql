-- ====================================================================
-- QUERIES ĐỂ SELECT CÁC RECORD CỦA BRANCH_ID = 1
-- ====================================================================

-- 1. Select tất cả invoice của branch_id = 1
-- Invoice có thể liên kết với court_booking hoặc service_booking
SELECT I.*
FROM invoice I
LEFT JOIN court_booking CB ON I.court_booking_id = CB.id
LEFT JOIN service_booking SB ON I.service_booking_id = SB.id
LEFT JOIN court_booking CB_SB ON SB.court_booking_id = CB_SB.id
LEFT JOIN court C ON (CB.court_id = C.id OR CB_SB.court_id = C.id)
WHERE C.branch_id = 1;
GO

-- 2. Select booking_slots với thông tin chi tiết của branch_id = 1
SELECT 
    BS.*,
    CB.id AS court_booking_id,
    CB.booking_date,
    CB.status AS booking_status,
    C.id AS court_id,
    C.name AS court_name,
    C.branch_id
FROM booking_slots BS
INNER JOIN court_booking CB ON BS.court_booking_id = CB.id
INNER JOIN court C ON CB.court_id = C.id
WHERE C.branch_id = 1;
GO

-- 3. Select refund_info với thông tin chi tiết của branch_id = 1
SELECT 
    RI.*,
    I.id AS invoice_id,
    I.total_amount AS invoice_total_amount,
    I.status AS invoice_status,
    I.payment_method AS invoice_payment_method,
    CB.id AS court_booking_id,
    CB.booking_date,
    CB.status AS booking_status,
    C.id AS court_id,
    C.name AS court_name,
    C.branch_id,
    CASE 
        WHEN I.court_booking_id IS NOT NULL THEN N'Refund cho đặt sân'
        WHEN I.service_booking_id IS NOT NULL THEN N'Refund cho dịch vụ'
    END AS refund_type
FROM refund_info RI
INNER JOIN invoice I ON RI.invoice_id = I.id
LEFT JOIN court_booking CB ON I.court_booking_id = CB.id
LEFT JOIN service_booking SB ON I.service_booking_id = SB.id
LEFT JOIN court_booking CB_SB ON SB.court_booking_id = CB_SB.id
LEFT JOIN court C ON (CB.court_id = C.id OR CB_SB.court_id = C.id)
WHERE C.branch_id = 1;
GO

select * 
from employee e 
    join account a
    on e.user_id = a.id
where a.role_id = 1
-- 4: Lấy thông tin cấu hình từ branch
SELECT cancel_fee_before_24h_percent, cancel_fee_within_24h_percent FROM branch WHERE id=1