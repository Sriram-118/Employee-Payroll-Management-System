CREATE DATABASE PayrollManagementDB;
GO

USE PayrollManagementDB;
GO


CREATE TABLE Departments (
    DepartmentID   INT IDENTITY(1,1) PRIMARY KEY,
    DepartmentName NVARCHAR(100) NOT NULL UNIQUE,
    ManagerID      INT NULL,  -- FK added after Employees table
    Location       NVARCHAR(100),
    CreatedAt      DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Employees (
    EmployeeID     INT IDENTITY(1,1) PRIMARY KEY,
    FirstName      NVARCHAR(50)  NOT NULL,
    LastName       NVARCHAR(50)  NOT NULL,
    Email          NVARCHAR(100) NOT NULL UNIQUE,
    Phone          NVARCHAR(20),
    HireDate       DATE          NOT NULL,
    DepartmentID   INT           NOT NULL,
    JobTitle       NVARCHAR(100),
    EmploymentType NVARCHAR(20)  CHECK (EmploymentType IN ('Full-Time','Part-Time','Contract')) DEFAULT 'Full-Time',
    IsActive       BIT           DEFAULT 1,
    CreatedAt      DATETIME      DEFAULT GETDATE(),
    CONSTRAINT FK_Employees_Department FOREIGN KEY (DepartmentID) REFERENCES Departments(DepartmentID)
);
GO

ALTER TABLE Departments
    ADD CONSTRAINT FK_Departments_Manager FOREIGN KEY (ManagerID) REFERENCES Employees(EmployeeID);
GO

CREATE TABLE SalaryStructure (
    SalaryID       INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID     INT           NOT NULL UNIQUE,
    BasicSalary    DECIMAL(12,2) NOT NULL CHECK (BasicSalary >= 0),
    HouseAllowance DECIMAL(12,2) DEFAULT 0,
    TransportAllow DECIMAL(12,2) DEFAULT 0,
    MedicalAllow   DECIMAL(12,2) DEFAULT 0,
    OtherAllowance DECIMAL(12,2) DEFAULT 0,
    EffectiveDate  DATE          NOT NULL DEFAULT GETCAST(GETDATE() AS DATE),
    CONSTRAINT FK_Salary_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID)
);
GO

CREATE TABLE AttendanceRecords (
    AttendanceID   INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID     INT  NOT NULL,
    AttendanceDate DATE NOT NULL,
    CheckIn        TIME,
    CheckOut       TIME,
    Status         NVARCHAR(20) CHECK (Status IN ('Present','Absent','Half-Day','Leave','Holiday')) DEFAULT 'Present',
    LateMinutes    INT DEFAULT 0,
    CONSTRAINT FK_Attendance_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID),
    CONSTRAINT UQ_Attendance UNIQUE (EmployeeID, AttendanceDate)
);
GO

CREATE TABLE LeaveRequests (
    LeaveID      INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID   INT          NOT NULL,
    LeaveType    NVARCHAR(50) CHECK (LeaveType IN ('Annual','Sick','Maternity','Paternity','Unpaid')) NOT NULL,
    StartDate    DATE         NOT NULL,
    EndDate      DATE         NOT NULL,
    TotalDays    AS (DATEDIFF(DAY, StartDate, EndDate) + 1) PERSISTED,
    Status       NVARCHAR(20) CHECK (Status IN ('Pending','Approved','Rejected')) DEFAULT 'Pending',
    ApprovedBy   INT,
    RequestedOn  DATETIME     DEFAULT GETDATE(),
    CONSTRAINT FK_Leave_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID)
);
GO

CREATE TABLE PayrollRecords (
    PayrollID        INT IDENTITY(1,1) PRIMARY KEY,
    EmployeeID       INT           NOT NULL,
    PayPeriodMonth   INT           NOT NULL CHECK (PayPeriodMonth BETWEEN 1 AND 12),
    PayPeriodYear    INT           NOT NULL,
    BasicSalary      DECIMAL(12,2) NOT NULL,
    TotalAllowances  DECIMAL(12,2) DEFAULT 0,
    GrossSalary      DECIMAL(12,2),
    TaxDeduction     DECIMAL(12,2) DEFAULT 0,
    ProvidentFund    DECIMAL(12,2) DEFAULT 0,
    LateDeduction    DECIMAL(12,2) DEFAULT 0,
    AbsenceDeduction DECIMAL(12,2) DEFAULT 0,
    OtherDeductions  DECIMAL(12,2) DEFAULT 0,
    TotalDeductions  DECIMAL(12,2),
    NetSalary        DECIMAL(12,2),
    DaysWorked       INT,
    DaysAbsent       INT,
    ProcessedOn      DATETIME      DEFAULT GETDATE(),
    PaymentStatus    NVARCHAR(20)  CHECK (PaymentStatus IN ('Pending','Paid','On-Hold')) DEFAULT 'Pending',
    CONSTRAINT FK_Payroll_Employee FOREIGN KEY (EmployeeID) REFERENCES Employees(EmployeeID),
    CONSTRAINT UQ_Payroll UNIQUE (EmployeeID, PayPeriodMonth, PayPeriodYear)
);
GO

CREATE TABLE TaxBrackets (
    TaxBracketID INT IDENTITY(1,1) PRIMARY KEY,
    MinIncome    DECIMAL(12,2) NOT NULL,
    MaxIncome    DECIMAL(12,2),           -- NULL = no upper limit
    TaxRate      DECIMAL(5,2)  NOT NULL,  -- percentage
    Description  NVARCHAR(100)
);
GO

INSERT INTO TaxBrackets (MinIncome, MaxIncome, TaxRate, Description) VALUES
(0,       25000,  0,    'Tax Free'),
(25001,   50000,  5,    '5% Bracket'),
(50001,   100000, 10,   '10% Bracket'),
(100001,  200000, 20,   '20% Bracket'),
(200001,  NULL,   30,   '30% Bracket');
GO


CREATE OR ALTER TRIGGER trg_CalculateLateMinutes
ON AttendanceRecords
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE a
    SET a.LateMinutes = CASE
        WHEN i.CheckIn > '09:00:00' AND i.Status = 'Present'
            THEN DATEDIFF(MINUTE, '09:00:00', i.CheckIn)
        ELSE 0
    END
    FROM AttendanceRecords a
    INNER JOIN inserted i ON a.AttendanceID = i.AttendanceID;
END;
GO

CREATE OR ALTER TRIGGER trg_ValidatePayroll
ON PayrollRecords
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

       UPDATE p
    SET
        p.GrossSalary     = i.BasicSalary + i.TotalAllowances,
        p.TotalDeductions = i.TaxDeduction + i.ProvidentFund + i.LateDeduction
                          + i.AbsenceDeduction + i.OtherDeductions,
        p.NetSalary       = (i.BasicSalary + i.TotalAllowances)
                          - (i.TaxDeduction + i.ProvidentFund + i.LateDeduction
                             + i.AbsenceDeduction + i.OtherDeductions)
    FROM PayrollRecords p
    INNER JOIN inserted i ON p.PayrollID = i.PayrollID;

        IF EXISTS (SELECT 1 FROM PayrollRecords WHERE PayrollID IN (SELECT PayrollID FROM inserted) AND NetSalary < 0)
    BEGIN
        RAISERROR('Net salary cannot be negative. Check deductions.', 16, 1);
        ROLLBACK TRANSACTION;
    END
END;
GO

CREATE OR ALTER TRIGGER trg_MinAttendanceCheck
ON PayrollRecords
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE p
    SET p.PaymentStatus = 'On-Hold'
    FROM PayrollRecords p
    INNER JOIN inserted i ON p.PayrollID = i.PayrollID
    WHERE i.DaysWorked IS NOT NULL
      AND i.DaysAbsent IS NOT NULL
      AND (CAST(i.DaysAbsent AS FLOAT) / NULLIF(i.DaysWorked + i.DaysAbsent, 0)) > 0.5;
END;
GO

CREATE OR ALTER TRIGGER trg_PreventEmployeeDeletion
ON Employees
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 FROM PayrollRecords p
        INNER JOIN deleted d ON p.EmployeeID = d.EmployeeID
    )
    BEGIN
        RAISERROR('Cannot delete employee with existing payroll records. Deactivate instead.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    DELETE FROM Employees WHERE EmployeeID IN (SELECT EmployeeID FROM deleted);
END;
GO

CREATE OR ALTER PROCEDURE sp_ProcessMonthlyPayroll
    @Month INT,
    @Year  INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @WorkingDays INT = 22; -- configurable
    DECLARE @LatePenaltyPerMin DECIMAL(8,4) = 5.00; -- currency per minute

    INSERT INTO PayrollRecords (
        EmployeeID, PayPeriodMonth, PayPeriodYear,
        BasicSalary, TotalAllowances,
        TaxDeduction, ProvidentFund, LateDeduction, AbsenceDeduction,
        DaysWorked, DaysAbsent
    )
    SELECT
        e.EmployeeID,
        @Month,
        @Year,
        ss.BasicSalary,
        (ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) AS TotalAllowances,
        -- Tax: progressive bracket lookup
        CASE
            WHEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) <= 25000  THEN 0
            WHEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) <= 50000  THEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) * 0.05
            WHEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) <= 100000 THEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) * 0.10
            WHEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) <= 200000 THEN (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) * 0.20
            ELSE (ss.BasicSalary + ss.HouseAllowance + ss.TransportAllow + ss.MedicalAllow + ss.OtherAllowance) * 0.30
        END AS TaxDeduction,
        ss.BasicSalary * 0.05 AS ProvidentFund,    -- 5% PF
        ISNULL(att.TotalLateMinutes, 0) * @LatePenaltyPerMin AS LateDeduction,
        -- Absence deduction = (BasicSalary / WorkingDays) * DaysAbsent
        (ss.BasicSalary / @WorkingDays) * ISNULL(att.DaysAbsent, 0) AS AbsenceDeduction,
        ISNULL(att.DaysPresent, 0) AS DaysWorked,
        ISNULL(att.DaysAbsent, 0)  AS DaysAbsent
    FROM Employees e
    INNER JOIN SalaryStructure ss ON e.EmployeeID = ss.EmployeeID
    OUTER APPLY (
        SELECT
            SUM(CASE WHEN Status IN ('Present','Half-Day') THEN 1 ELSE 0 END) AS DaysPresent,
            SUM(CASE WHEN Status = 'Absent' THEN 1 ELSE 0 END) AS DaysAbsent,
            SUM(LateMinutes) AS TotalLateMinutes
        FROM AttendanceRecords
        WHERE EmployeeID = e.EmployeeID
          AND MONTH(AttendanceDate) = @Month
          AND YEAR(AttendanceDate)  = @Year
    ) att
    WHERE e.IsActive = 1
      AND NOT EXISTS (
          SELECT 1 FROM PayrollRecords
          WHERE EmployeeID = e.EmployeeID
            AND PayPeriodMonth = @Month
            AND PayPeriodYear  = @Year
      );

    PRINT CONCAT('Payroll processed for ', @Month, '/', @Year);
END;
GO


CREATE OR ALTER VIEW vw_PayrollSummary AS
SELECT
    p.PayrollID,
    p.PayPeriodMonth,
    p.PayPeriodYear,
    e.EmployeeID,
    CONCAT(e.FirstName, ' ', e.LastName) AS EmployeeName,
    d.DepartmentName,
    e.JobTitle,
    p.BasicSalary,
    p.TotalAllowances,
    p.GrossSalary,
    p.TaxDeduction,
    p.ProvidentFund,
    p.LateDeduction,
    p.AbsenceDeduction,
    p.OtherDeductions,
    p.TotalDeductions,
    p.NetSalary,
    p.DaysWorked,
    p.DaysAbsent,
    p.PaymentStatus,
    p.ProcessedOn
FROM PayrollRecords p
INNER JOIN Employees   e ON p.EmployeeID   = e.EmployeeID
INNER JOIN Departments d ON e.DepartmentID = d.DepartmentID;
GO

CREATE OR ALTER VIEW vw_DepartmentSalarySummary AS
SELECT
    d.DepartmentID,
    d.DepartmentName,
    COUNT(DISTINCT p.EmployeeID)  AS TotalEmployees,
    AVG(p.BasicSalary)            AS AvgBasicSalary,
    SUM(p.GrossSalary)            AS TotalGrossSalary,
    SUM(p.TotalDeductions)        AS TotalDeductions,
    SUM(p.NetSalary)              AS TotalNetSalary,
    SUM(p.TaxDeduction)           AS TotalTaxCollected,
    p.PayPeriodMonth,
    p.PayPeriodYear
FROM PayrollRecords p
INNER JOIN Employees   e ON p.EmployeeID   = e.EmployeeID
INNER JOIN Departments d ON e.DepartmentID = d.DepartmentID
GROUP BY d.DepartmentID, d.DepartmentName, p.PayPeriodMonth, p.PayPeriodYear;
GO

CREATE OR ALTER VIEW vw_AttendanceSummary AS
SELECT
    e.EmployeeID,
    CONCAT(e.FirstName, ' ', e.LastName) AS EmployeeName,
    d.DepartmentName,
    MONTH(a.AttendanceDate)   AS AttendanceMonth,
    YEAR(a.AttendanceDate)    AS AttendanceYear,
    COUNT(*)                              AS TotalRecords,
    SUM(CASE WHEN a.Status = 'Present'  THEN 1 ELSE 0 END) AS DaysPresent,
    SUM(CASE WHEN a.Status = 'Absent'   THEN 1 ELSE 0 END) AS DaysAbsent,
    SUM(CASE WHEN a.Status = 'Half-Day' THEN 1 ELSE 0 END) AS HalfDays,
    SUM(CASE WHEN a.Status = 'Leave'    THEN 1 ELSE 0 END) AS LeaveDays,
    SUM(a.LateMinutes)                    AS TotalLateMinutes,
    CAST(
        SUM(CASE WHEN a.Status = 'Present' THEN 1.0 ELSE 0 END) /
        NULLIF(COUNT(*), 0) * 100
    AS DECIMAL(5,2)) AS AttendancePct
FROM AttendanceRecords a
INNER JOIN Employees   e ON a.EmployeeID   = e.EmployeeID
INNER JOIN Departments d ON e.DepartmentID = d.DepartmentID
GROUP BY e.EmployeeID, e.FirstName, e.LastName, d.DepartmentName,
         MONTH(a.AttendanceDate), YEAR(a.AttendanceDate);
GO



SELECT TOP 5
    EmployeeName,
    DepartmentName,
    JobTitle,
    GrossSalary,
    TotalDeductions,
    NetSalary
FROM vw_PayrollSummary
WHERE PayPeriodMonth = MONTH(GETDATE())
  AND PayPeriodYear  = YEAR(GETDATE())
ORDER BY NetSalary DESC;
GO

SELECT
    ps.EmployeeName,
    ps.DepartmentName,
    ps.PayPeriodMonth,
    ps.PayPeriodYear,
    ps.LateDeduction,
    ps.NetSalary
FROM vw_PayrollSummary ps
WHERE ps.LateDeduction > 500
ORDER BY ps.LateDeduction DESC;
GO

SELECT
    PayPeriodYear,
    PayPeriodMonth,
    SUM(TaxDeduction)  AS TotalTaxCollected,
    SUM(ProvidentFund) AS TotalPFCollected,
    SUM(NetSalary)     AS TotalNetPaid,
    COUNT(DISTINCT EmployeeID) AS EmployeeCount
FROM vw_PayrollSummary
GROUP BY PayPeriodYear, PayPeriodMonth
ORDER BY PayPeriodYear, PayPeriodMonth;
GO

SELECT
    EmployeeName,
    DepartmentName,
    AttendanceMonth,
    AttendanceYear,
    DaysPresent,
    DaysAbsent,
    AttendancePct
FROM vw_AttendanceSummary
WHERE AttendancePct < 75
ORDER BY AttendancePct ASC;
GO

SELECT
    d.DepartmentName,
    SUM(p.GrossSalary)  AS YTD_GrossSalary,
    SUM(p.NetSalary)    AS YTD_NetSalary,
    SUM(p.TaxDeduction) AS YTD_TaxDeducted,
    COUNT(DISTINCT p.EmployeeID) AS HeadCount
FROM PayrollRecords p
INNER JOIN Employees   e ON p.EmployeeID   = e.EmployeeID
INNER JOIN Departments d ON e.DepartmentID = d.DepartmentID
WHERE p.PayPeriodYear = YEAR(GETDATE())
GROUP BY d.DepartmentName
ORDER BY YTD_NetSalary DESC;
GO
