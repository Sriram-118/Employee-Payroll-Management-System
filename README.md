Employee Payroll Management System
Overview
A fully relational payroll database designed to manage employees departments attendance records and salary structures. The system automates payroll calculations enforces business rules through triggers and provides rich reporting through views and complex queries
Features
Designed and implemented a relational payroll database to manage employees departments attendance and salary structures. Created triggers to update payroll records and enforce business rules such as late penalties and minimum attendance validation. Built views and complex queries for payroll reporting department wise salary summaries and tax calculations
Database Tables

Departments
Employees
SalaryStructure
AttendanceRecords
LeaveRequests
PayrollRecords
TaxBrackets

Triggers

Auto calculates late minutes on attendance insert
Validates and computes net salary on payroll insert
Flags payroll as on hold if attendance falls below 50 percent
Prevents deletion of employees with existing payroll history

Stored Procedures

sp_ProcessMonthlyPayroll processes full payroll for all active employees for a given month

Views

vw_PayrollSummary full payroll details per employee per month
vw_DepartmentSalarySummary department wise salary aggregation
vw_AttendanceSummary monthly attendance stats per employee

How to Run
1 Open SQL Server Management Studio
2 Run the script employee_payroll_management.sql
3 The database PayrollManagementDB will be created automatically with all tables triggers procedures views and sample data
