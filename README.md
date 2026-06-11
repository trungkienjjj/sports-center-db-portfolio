# VietSport Sports Center Database

A SQL Server portfolio version of a team-built sports-center management database. The system models branches, courts, bookings, services, inventory, invoices, refunds, employees, shifts, salaries, and customer memberships across 25 relational tables.

## Attribution and my contribution

The original system was developed by a five-person course team. This repository is a portfolio copy intended to demonstrate my own work without claiming sole authorship of the full project.

My contributions include:

- Relational schema design and normalization work
- Business constraints, triggers, and stored procedures
- Booking-conflict and timing validation
- Inventory and transactional-integrity rules
- Portfolio documentation and runnable sample organization

## Core behavior

- Prevent overlapping bookings for the same court
- Require online bookings to be created sufficiently before the start time
- Limit online booking counts according to business rules
- Validate non-negative salary, allowance, commission, price, and inventory fields
- Deduct service inventory automatically
- Enforce unique accounts and reference data
- Model invoicing, discounts, refunds, loyalty points, shifts, leave, and salary history

## Schema overview

The 25 tables are organized in dependency phases so referenced records are created before dependent records. Major domains include:

- Organization: `branch`, `role`, `account`, `employee`
- Courts: `court_type`, `court`, `court_booking`, `booking_slots`
- Services: `service`, `branch_service`, `service_booking`, `service_booking_item`
- Finance: `invoice`, `discount_policy`, `invoice_discount`, `refund_info`
- Workforce: `work_shift`, `shift_assignment`, `leave_request`, `salary_history`

## Run order

Use SQL Server 2019 or newer. Review scripts before running because the database creation script may replace an existing `SportsCenterDB` database.

```text
1. create_db.sql
2. create_data.sql
3. create_constraints.sql or the repository's constraint script
4. stored procedures required for the scenario being tested
```

## Example rules

| Rule | Purpose |
|---|---|
| `TG_R1401` | Limit online bookings per day |
| `TG_R1402` | Enforce advance online booking time |
| `TG_R1403` | Reject overlapping court bookings |
| `TG_R1404` | Validate and deduct service inventory |

## Technology

- SQL Server / T-SQL
- Stored procedures and triggers
- Foreign keys, checks, unique constraints, and transactions

## Limitations

- This repository demonstrates the database layer, not a deployed end-user application.
- Team-authored components remain attributed to the original project members.
- Sample credentials and data are for demonstration only.

Portfolio: [trungkienjjj.github.io](https://trungkienjjj.github.io)
