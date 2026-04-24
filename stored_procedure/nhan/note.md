# Stored Procedures - Nhan (Receptionist Functions)

This folder contains stored procedures related to receptionist operations for court and service bookings.

## 1. sp_receptionist_calculate_slots_price
**Purpose:** Calculate the price for booking slots on a specific court for a given date.

**Parameters:**
- `@court_id INT` - Court ID
- `@date DATE` - Booking date
- `@slots NVARCHAR(MAX)` - JSON array of time slots with start_time and end_time

**Functionality:**
- Retrieves base hourly price from the court
- Applies weekend charge if the date falls on Saturday/Sunday
- Applies holiday charge if the date matches any holiday in the holidays table
- Applies night charge for slots starting at or after 17:00
- Calculates total price for each slot: base_price × (1 + holiday_charge + weekend_charge + night_charge)
- Returns a table with pricing details for each slot

**Returns:** Table with columns: start_time, end_time, base_price, holiday_charge, weekend_charge, night_charge, total_price

---

## 2. sp_receptionist_create_court_booking
**Purpose:** Create a new court booking with multiple time slots.

**Parameters:**
- `@creator INT` - Employee ID creating the booking
- `@customer_id INT` - Customer ID
- `@court_id INT` - Court ID
- `@booking_date DATE` - Date of booking
- `@slots NVARCHAR(MAX)` - JSON array of time slots
- `@by_month BIT` - Monthly booking flag
- `@branch_id INT` - Branch ID

**Functionality:**
- Validates no overlapping bookings exist for the same court and date
- Calculates applicable charges (weekend, holiday, night)
- Creates a court_booking record
- Inserts all booking_slots associated with the booking
- Uses transaction to ensure data consistency

**Error Handling:**
- Throws error if schedule conflicts detected
- Rollback on any failure

---

## 3. sp_receptionist_create_service_booking
**Purpose:** Create a service booking with multiple items (rackets, lockers, bibs, trainers, referees, etc.).

**Parameters:**
- `@court_booking_id INT` - Associated court booking ID
- `@employee_id INT` - Receptionist creating the booking (optional)
- `@items NVARCHAR(MAX)` - JSON array of service items with branch_service_id, quantity, start_time, end_time, by_month, employee_id

**Functionality:**
- Creates a service_booking record
- Processes each service item based on stock_type:
  - **theo_thoi_gian (time-based)**: Items like rackets, lockers - validates availability during the time slot
  - **tieu_hao (consumable)**: Items like water bottles - reduces global stock immediately
  - **hlv_trong_tai (trainer/referee)**: Validates trainer/referee availability and assigns them
- Validates stock thresholds before booking
- Creates service_booking_item records
- For trainers/referees: creates service_booking_trainer_referee records
- Uses comprehensive availability checks for trainers/referees including leave requests and shift assignments

**Error Handling:**
- Throws error if insufficient stock
- Throws error if trainer/referee not available
- Transaction rollback on failure

---

## 4. sp_receptionist_get_booking_slots_of_court
**Purpose:** Retrieve all booked slots for a specific court on a given date.

**Parameters:**
- `@court_id INT` - Court ID
- `@date DATE` - Date to check

**Functionality:**
- Returns all active (non-cancelled) booking slots for the specified court and date
- Includes customer information for each booking

**Returns:** Table with columns: id, start_time, end_time, status, customer_name, customer_phone_number

---

## 5. sp_receptionist_get_customer_court_bookings
**Purpose:** View all court bookings for a specific customer.

**Parameters:**
- `@customer_id INT` - Customer ID

**Functionality:**
- Retrieves all court bookings for the customer
- Calculates total price including all charges
- Returns booking slots as nested JSON
- Groups results by booking ID

**Returns:** Table with booking details including: id, status, booking_date, by_month, court_name, court_type, total_price, slots (JSON)

---

## 6. sp_receptionist_get_service_booking_details
**Purpose:** Get detailed information about a specific service booking.

**Parameters:**
- `@service_booking_id INT` - Service booking ID

**Functionality:**
- Returns two result sets:
  1. List of service_booking_items with service details, prices, quantities, and times
  2. List of assigned trainers/referees with their roles and booked prices

**Returns:** 
- Result Set 1: service_booking_item details
- Result Set 2: trainer/referee assignments

---

## 7. sp_receptionist_get_service_booking_info
**Purpose:** Get all service bookings associated with a court booking.

**Parameters:**
- `@court_booking_id INT` - Court booking ID

**Functionality:**
- Retrieves all service bookings linked to the court booking
- Includes receptionist information

**Returns:** Table with columns: service_booking_id, court_booking_id, receptionist_id, receptionist_name, status, created_at

---

## 8. sp_receptionist_get_services
**Purpose:** View all services available at a branch.

**Parameters:**
- `@branch_id INT` - Branch ID

**Functionality:**
- Retrieves all branch services with pricing and stock information
- Shows service details including unit, name, rental type, and stock levels

**Returns:** Table with columns: id, unit, name, rental_type, unit_price, current_stock, min_stock_threshold, status

---

## 9. sp_receptionist_get_trainer_referee
**Purpose:** Get list of available trainers/referees for a court booking.

**Parameters:**
- `@court_booking_id INT` - Court booking ID

**Functionality:**
- Validates trainer/referee availability based on:
  - Branch assignment
  - Employment status (not terminated)
  - No approved leave on booking date
  - Not already booked for overlapping time slots
  - Has shift assignment covering the earliest booking slot start time
- Returns qualified trainers/referees with their details

**Returns:** Table with columns: id, full_name, status, num_of_exp, university, specialization, price_per_hour, sport_type, role

---

## 10. sp_receptionist_list_courts_of_branch
**Purpose:** List all courts at a branch filtered by court type.

**Parameters:**
- `@branch_id INT` - Branch ID
- `@court_type_id INT` - Court type ID

**Functionality:**
- Simple query to retrieve courts matching branch and type criteria

**Returns:** Table with columns: id, status, name

---

## 11. sp_receptionist_update_court_booking
**Purpose:** Update an existing court booking (change court, date, or time slots).

**Parameters:**
- `@booking_id INT` - Court booking ID to update
- `@new_court_id INT` - New court ID
- `@new_booking_date DATE` - New booking date
- `@new_slots NVARCHAR(MAX)` - New time slots JSON
- `@branch_id INT` - Branch ID

**Functionality:**
- Validates no conflicts with OTHER bookings (allows overlap with its own old slots)
- Recalculates all charges (weekend, holiday, night) based on new date/court
- Intelligently handles slot updates:
  - Keeps existing slots that appear in the new slots (preserves slot IDs)
  - Soft deletes (cancels) old slots not in the new set
  - Inserts only truly new slots
- Updates court_booking with new court, date, and charges
- Uses transaction for data consistency

**Error Handling:**
- Throws error if booking doesn't exist
- Throws error if court doesn't exist
- Throws error if schedule conflicts with other bookings
- Transaction rollback on failure

---

## Technical Notes

### Stock Management
The system handles three types of stock:
1. **Time-based (theo_thoi_gian)**: Rackets, lockers, bibs - availability checked per time slot
2. **Consumable (tieu_hao)**: Water bottles, towels - deducted from global stock
3. **Trainer/Referee (hlv_trong_tai)**: Per-slot booking with complex availability validation

### Pricing Model
Total price = base_price × (1 + holiday_charge + weekend_charge + night_charge)
- Night charge applies to slots starting at or after 17:00
- All charges are multiplicative factors (e.g., 0.2 = 20% surcharge)

### Transaction Management
All procedures use transactions with proper error handling and rollback mechanisms to ensure data consistency.