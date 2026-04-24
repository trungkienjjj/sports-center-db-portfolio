/*
 * =================================================================
 * BƯỚC 1: DỌN DẸP VÀ TẠO LẠI DATABASE
 * =================================================================
 */

-- Chuyển về master để có thể thao tác
USE master;
GO

-- Ép buộc ngắt mọi kết nối đến database cũ
IF DB_ID('SportsCenterDB') IS NOT NULL
BEGIN
    ALTER DATABASE SportsCenterDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    
    -- Xóa database cũ
    DROP DATABASE SportsCenterDB;
END
GO

-- Tạo lại database mới
CREATE DATABASE SportsCenterDB;
GO

-- Bắt đầu làm việc trên database mới
USE SportsCenterDB;
GO

PRINT 'DATABASE IS READY. CREATING 25 TABLES...';
GO
/*
 * =================================================================
 * BƯỚC 2: TẠO 25 BẢNG VÀ MỐI QUAN HỆ (THEO ERD PDF - BẢN SẠCH)
 * =================================================================
 */

-- Phải ở đúng database
USE SportsCenterDB;
GO

/* * ==========================================
 * PHASE 1: CÁC BẢNG ĐỘC LẬP (KHÔNG CÓ FK)
 * ==========================================
 */

-- branch
CREATE TABLE [branch] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(255) NOT NULL,
    [address] NVARCHAR(500) NOT NULL,
    [hotline] VARCHAR(20) NOT NULL,
    [late_time_limit] INT NOT NULL,
    [max_courts_per_day_per_user] INT NOT NULL,
    [shift_pay] DECIMAL(10, 2) NOT NULL,
    [shift_absence_penalty] DECIMAL(10, 2) NOT NULL,
    [loyalty_point_rate] DECIMAL(5, 2) NOT NULL,
    [cancel_fee_before_24h_percent] DECIMAL(5, 2) NOT NULL,
    [cancel_fee_within_24h_percent] DECIMAL(5, 2) NOT NULL,
    [no_show_fee_percent] DECIMAL(5, 2) NOT NULL,
    [night_booking_additional_charge] DECIMAL(10, 2) NOT NULL,
    [holiday_booking_additional_charge] DECIMAL(10, 2) NOT NULL,
    [weekend_booking_additional_charge] DECIMAL(10, 2) NOT NULL,
    [open_time] TIME(0) NOT NULL,
    [close_time] TIME(0) NOT NULL,
);
GO

-- court_type
CREATE TABLE [court_type] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(100) UNIQUE NOT NULL,
    [rent_duration] INT NOT NULL -- (ví dụ: 60 phút, 90 phút)
);
GO

-- work_shift
CREATE TABLE [work_shift] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [date] DATE NOT NULL,
    [start_time] TIME NOT NULL,
    [end_time] TIME NOT NULL,
    [required_count] INT NOT NULL
);
GO

-- role
CREATE TABLE [role] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(100) NOT NULL UNIQUE
);
GO

-- customer_level
CREATE TABLE [customer_level] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(100) NOT NULL UNIQUE,
    [discount_rate] DECIMAL(5, 2) NOT NULL,
    [minimum_point] INT
);
GO

-- service
CREATE TABLE [service] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(255) NOT NULL UNIQUE,
    [unit] NVARCHAR(50) NOT NULL,
    [rental_type] NVARCHAR(100) NOT NULL,
    [stock_type] NVARCHAR(100) NOT NULL
);
GO

/* * ==========================================
 * PHASE 2: CÁC BẢNG CÓ FK CẤP 1
 * ==========================================
 */

-- account
CREATE TABLE [account] (
    [id] uniqueidentifier DEFAULT NEWID() PRIMARY KEY,
    [username] VARCHAR(255) UNIQUE NOT NULL,
    [password] VARCHAR(500) NOT NULL, -- Sẽ lưu dạng hash
    [is_active] BIT DEFAULT 1,
    [role_id] INT NOT NULL,
    CONSTRAINT [FK_account_role] FOREIGN KEY ([role_id]) REFERENCES [role]([id])
);
GO

-- discount_policy
CREATE TABLE [discount_policy] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(255) NOT NULL,
    [type] NVARCHAR(50) NOT NULL,
    [discount_value] DECIMAL(10, 2) NOT NULL,
    [description] NVARCHAR(500),
    [branch_id] INT NOT NULL,
    CONSTRAINT [FK_discount_policy_branch] FOREIGN KEY ([branch_id]) REFERENCES [branch]([id])
);
GO

/* * ==========================================
 * PHASE 3: CÁC BẢNG CÓ FK CẤP 2
 * ==========================================
 */

-- customer
CREATE TABLE [customer] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [full_name] NVARCHAR(255) NOT NULL,
    [dob] DATE NOT NULL,
    [gender] NVARCHAR(10) NOT NULL,
    [id_card_number] VARCHAR(20) UNIQUE NOT NULL,
    [address] NVARCHAR(500) NOT NULL,
    [phone_number] VARCHAR(20) UNIQUE NOT NULL,
    [email] VARCHAR(255) UNIQUE NOT NULL,
    [bonus_point] INT DEFAULT 0,
    [customer_level_id] INT NOT NULL,
    [user_id] uniqueidentifier NOT NULL, -- Khóa ngoại duy nhất tới account
    CONSTRAINT [FK_customer_customer_level] FOREIGN KEY ([customer_level_id]) REFERENCES [customer_level]([id]),
    CONSTRAINT [FK_customer_account] FOREIGN KEY ([user_id]) REFERENCES [account]([id])
);
GO

-- employee
CREATE TABLE [employee] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [full_name] NVARCHAR(255) NOT NULL,
    [gender] NVARCHAR(10) NOT NULL,
    [dob] DATE NOT NULL,
    [id_card_number] VARCHAR(20) UNIQUE NOT NULL,
    [address] NVARCHAR(500) NOT NULL,
    [phone_number] VARCHAR(20) UNIQUE NOT NULL,
    [email] VARCHAR(255) UNIQUE NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [commission_rate] DECIMAL(5, 2),
    [base_salary] DECIMAL(10, 2) NOT NULL,
    [base_allowance] DECIMAL(10, 2),
    [user_id] uniqueidentifier NOT NULL, -- Khóa ngoại duy nhất tới account
    [branch_id] INT NOT NULL,
    CONSTRAINT [FK_employee_account] FOREIGN KEY ([user_id]) REFERENCES [account]([id]),
    CONSTRAINT [FK_employee_branch] FOREIGN KEY ([branch_id]) REFERENCES [branch]([id])
);
GO

-- court
CREATE TABLE [court] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(100) NOT NULL UNIQUE,
    [status] NVARCHAR(50) NOT NULL,
    [capacity] INT NOT NULL,
    [base_hourly_price] DECIMAL(10, 2) NOT NULL,
    [maintenance_date] DATE,
    [branch_id] INT NOT NULL,
    [court_type_id] INT NOT NULL,
    CONSTRAINT [FK_court_branch] FOREIGN KEY ([branch_id]) REFERENCES [branch]([id]),
    CONSTRAINT [FK_court_court_type] FOREIGN KEY ([court_type_id]) REFERENCES [court_type]([id])
);
GO

-- branch_service
CREATE TABLE [branch_service] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [unit_price] DECIMAL(10, 2) NOT NULL,
    [current_stock] INT NOT NULL,
    [min_stock_threshold] INT NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [branch_id] INT NOT NULL,
    [service_id] INT NOT NULL,
    CONSTRAINT [UQ_BranchService] UNIQUE ([branch_id], [service_id]),
    CONSTRAINT [FK_branch_service_branch] FOREIGN KEY ([branch_id]) REFERENCES [branch]([id]),
    CONSTRAINT [FK_branch_service_service] FOREIGN KEY ([service_id]) REFERENCES [service]([id])
);
GO

/* * ==========================================
 * PHASE 4: CÁC BẢNG CÓ FK CẤP 3
 * ==========================================
 */

-- trainer_referee_info
CREATE TABLE [trainer_referee_info] (
    [employee_id] INT PRIMARY KEY, -- Đây là FK và PK
    [num_of_exp] INT NOT NULL,
    [university] NVARCHAR(255),
    [specialization] NVARCHAR(255) NOT NULL,
    [price_per_hour] DECIMAL(10, 2) NOT NULL,
    [sport_type] NVARCHAR(100) NOT NULL,
    [role] NVARCHAR (50) NOT NULL, -- Huấn luyện viên hoặc trọng tài
    CONSTRAINT [FK_trainer_referee_info_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id]) ON DELETE CASCADE
);
GO

-- salary_history
CREATE TABLE [salary_history] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [year] INT NOT NULL,
    [month] INT NOT NULL,
    [base_salary] DECIMAL(10, 2) NOT NULL,
    [base_allowance] DECIMAL(10, 2),
    [commission_rate] DECIMAL(5, 2),
    [commission_amount] DECIMAL(10, 2),
    [deduction_penalty] DECIMAL(10, 2),
    [gross_pay] DECIMAL(10, 2) NOT NULL,
    [net_pay] DECIMAL(10, 2) NOT NULL,
    [payment_status] NVARCHAR(50) NOT NULL,
    [payment_method] NVARCHAR(50) NOT NULL,
    [paid_at] DATETIME NOT NULL,
    [employee_id] INT NOT NULL,
    CONSTRAINT [FK_salary_history_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id])
);
GO

-- leave_request
CREATE TABLE [leave_request] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [start_date] DATE NOT NULL,
    [end_date] DATE NOT NULL,
    [approval_status] NVARCHAR(50) NOT NULL,
    [reason] NVARCHAR(1000),
    [creator_id] INT NOT NULL, -- Người tạo đơn (Create)
    [approver_id] INT, -- Người duyệt (Approve)
    [replacer_id] INT, -- Người thay thế (Replace)
    CONSTRAINT [FK_leave_request_creator] FOREIGN KEY ([creator_id]) REFERENCES [employee]([id]),
    CONSTRAINT [FK_leave_request_approver] FOREIGN KEY ([approver_id]) REFERENCES [employee]([id]),
    CONSTRAINT [FK_leave_request_replacer] FOREIGN KEY ([replacer_id]) REFERENCES [employee]([id])
);
GO

-- court_booking
CREATE TABLE [court_booking] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [booking_date] DATE NOT NULL, -- Nếu theo tháng thì đây là ngày bắt đầu tính
    [type] NVARCHAR(50) NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [by_month] BIT DEFAULT 0 NOT NULL,
    [booked_base_price] DECIMAL(10, 2) NOT NULL, -- Giá đã đặt (có thể khác với giá gốc của sân)
    [holiday_charge] DECIMAL(10, 2) NOT NULL, -- Phụ thu ngày lễ (nếu có)
    [weekend_charge] DECIMAL(10, 2) NOT NULL, -- Phụ thu cuối tuần (nếu có)
    [customer_id] INT NOT NULL,
    [employee_id] INT,
    [court_id] INT NOT NULL,
    CONSTRAINT [FK_court_booking_customer] FOREIGN KEY ([customer_id]) REFERENCES [customer]([id]),
    CONSTRAINT [FK_court_booking_court] FOREIGN KEY ([court_id]) REFERENCES [court]([id]),
    CONSTRAINT [FK_court_booking_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id])
);
GO

-- shift_assignment
CREATE TABLE [shift_assignment] (
    [employee_id] INT,
    [work_shift_id] INT,
    [status] NVARCHAR(50) NOT NULL,
    [note] NVARCHAR(100),
    CONSTRAINT [PK_shift_assignment] PRIMARY KEY ([employee_id], [work_shift_id]), -- Khóa chính tổng hợp
    CONSTRAINT [FK_shift_assignment_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id]),
    CONSTRAINT [FK_shift_assignment_work_shift] FOREIGN KEY ([work_shift_id]) REFERENCES [work_shift]([id])
);
GO

/* * ==========================================
 * PHASE 5: CÁC BẢNG CÓ FK CẤP 4
 * ==========================================
 */

-- maintenance_report
CREATE TABLE [maintenance_report] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [work_description] NVARCHAR(1000) NOT NULL,
    [cost] DECIMAL(10, 2) NOT NULL,
    [material_used] NVARCHAR(1000),
    [post_maintenance_status] NVARCHAR(50) NOT NULL,
    [repairer_id] INT NOT NULL, -- Nhân viên bảo trì
    [court_id] INT NOT NULL,
    CONSTRAINT [FK_maintenance_report_repairer] FOREIGN KEY ([repairer_id]) REFERENCES [employee]([id]),
    CONSTRAINT [FK_maintenance_report_court] FOREIGN KEY ([court_id]) REFERENCES [court]([id])
);
GO

-- booking_slots
CREATE TABLE [booking_slots] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [start_time] DATETIME NOT NULL,
    [end_time] DATETIME NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [night_charge] DECIMAL(10, 2) NOT NULL, -- % phụ thu giờ tối (nếu có)
    [court_booking_id] INT NOT NULL,
    CONSTRAINT [UQ_CourtBookingSlot] UNIQUE ([court_booking_id], [start_time], [end_time]),
    CONSTRAINT [FK_booking_slots_court_booking] FOREIGN KEY ([court_booking_id]) REFERENCES [court_booking]([id]) ON DELETE CASCADE
);
GO

-- service_booking
CREATE TABLE [service_booking] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [status] NVARCHAR(50) NOT NULL,
    [court_booking_id] INT NOT NULL,
    [employee_id] INT, -- Nhân viên lễ tân (nếu có)
    CONSTRAINT [FK_service_booking_court_booking] FOREIGN KEY ([court_booking_id]) REFERENCES [court_booking]([id]),
    CONSTRAINT [FK_service_booking_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id])
);
GO

-- service_booking_item
CREATE TABLE [service_booking_item] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [quantity] INT NOT NULL,
    [start_time] DATETIME NOT NULL,
    [end_time] DATETIME NOT NULL,
    [by_month] BIT DEFAULT 0 NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [booked_unit_price] DECIMAL(10, 2) NOT NULL, -- Giá đã đặt (có thể khác với giá gốc trong branch_service)
    [service_booking_id] INT NOT NULL,
    [branch_service_id] INT NOT NULL,
    CONSTRAINT [FK_service_booking_item_branch_service] FOREIGN KEY ([branch_service_id]) REFERENCES [branch_service]([id]),
    CONSTRAINT [FK_service_booking_item_service_booking] FOREIGN KEY ([service_booking_id]) REFERENCES [service_booking]([id])
);
GO

-- invoice
CREATE TABLE [invoice] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [created_at] DATETIME DEFAULT GETDATE(),
    [total_amount] DECIMAL(10, 2) NOT NULL,
    [payment_method] NVARCHAR(50) NOT NULL,
    [status] NVARCHAR(50) NOT NULL,
    [employee_id] INT, -- Nhân viên thu ngân
    [service_booking_id] INT NULL,
    [court_booking_id] INT NULL,
    CONSTRAINT [FK_invoice_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id]),
    CONSTRAINT [FK_invoice_service_booking] FOREIGN KEY ([service_booking_id]) REFERENCES [service_booking]([id]),
    CONSTRAINT [FK_invoice_court_booking] FOREIGN KEY ([court_booking_id]) REFERENCES [court_booking]([id]),
    CONSTRAINT [CK_invoice_target] CHECK (
        ([service_booking_id] IS NULL AND [court_booking_id] IS NOT NULL) OR
        ([service_booking_id] IS NOT NULL AND [court_booking_id] IS NULL)
    )

    --[type] NVARCHAR(50) NOT NULL, -- service_booking hoặc court_booking
    --[target_id] INT NOT NULL, -- id của service_booking hoặc court_booking
    --CONSTRAINT [FK_invoice_court_booking] FOREIGN KEY ([target_id]) REFERENCES [court_booking]([id]),
    --CONSTRAINT [FK_invoice_service_booking] FOREIGN KEY ([target_id]) REFERENCES [service_booking]([id]),
);
GO

-- refund_info
CREATE TABLE [refund_info] (
    [id] INT IDENTITY (1, 1) PRIMARY KEY,
    [amount] DECIMAL(10, 2) NOT NULL,
    [reason] NVARCHAR (500) NOT NULL,
    [type] NVARCHAR (50) NOT NULL,
    [method] NVARCHAR (50) NOT NULL,
    [status] NVARCHAR (50) NOT NULL,
    [created_at] DATETIME DEFAULT GETDATE(),
    [processed_at] DATETIME,
    [notes] NVARCHAR (1000),
    [invoice_id] INT NOT NULL,
    CONSTRAINT [FK_refund_info_invoice] FOREIGN KEY ([invoice_id]) REFERENCES [invoice] ([id])
);
GO

/* * ==========================================
 * PHASE 6: BẢNG CÓ FK CẤP 5 (BẢNG NỐI CUỐI)
 * ==========================================
 */

-- invoice_discount
CREATE TABLE [invoice_discount] (
    [invoice_id] INT,
    [discount_policy_id] INT,
    CONSTRAINT [PK_invoice_discount] PRIMARY KEY ([invoice_id], [discount_policy_id]), -- Khóa chính tổng hợp
    CONSTRAINT [FK_invoice_discount_invoice] FOREIGN KEY ([invoice_id]) REFERENCES [invoice]([id]),
    CONSTRAINT [FK_invoice_discount_policy] FOREIGN KEY ([discount_policy_id]) REFERENCES [discount_policy]([id])
);
GO

-- service_booking_trainer_referee
CREATE TABLE [service_booking_trainer_referee] (
    [service_booking_item_id] INT, -- ID của dịch vụ kèm theo đặt sân
    [employee_id] INT, -- ID của huấn luyện viên/trọng tài
    [booked_price] DECIMAL(10, 2) NOT NULL, -- Giá đã đặt (có thể khác với giá gốc trong trainer_referee_info)
    CONSTRAINT [FK_service_booking_trainer_referee_service_booking_item] FOREIGN KEY ([service_booking_item_id]) REFERENCES [service_booking_item]([id]),
    CONSTRAINT [FK_service_booking_trainer_referee_employee] FOREIGN KEY ([employee_id]) REFERENCES [employee]([id])
);
GO

CREATE TABLE [holidays] (
    [id] INT IDENTITY(1,1) PRIMARY KEY,
    [name] NVARCHAR(100) NOT NULL,

    -- For one-time holiday
    [start_date] DATE NULL, 
    [end_date] DATE NULL,

    -- For recurring (yearly) holiday
    [rec_day]   TINYINT NULL,   -- 1–31
    [rec_month] TINYINT NULL,   -- 1–12
);

PRINT 'ALL 26 TABLES HAVE BEEN CREATED !';