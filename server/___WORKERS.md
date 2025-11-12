# Server Workers
This server runs automated background tasks to manage jobs, refunds, and user activity.

## Features

### Daily Worker
- Runs once a day automatically.
- **Closes jobs** that have passed their `end_date`.
- **Processes unfilled refunds** via Stripe for any pending transactions.
- **Fills Analytics DB** with relevant details for the day
- Schedules the next run automatically.
- Can be **manually triggered** via `/worker/run`.

### User Activity Tracking
- Updates `last_active` timestamp for users on every relevant API call.

### Logging
- Logs all task execution, scheduling, and Stripe/payment operations for monitoring.

## Manual Usage

### Run Worker via VSCode Task
```json
{
  "label": "RUN WORKER",
  "type": "shell",
  "command": "curl",
  "args": [
    "-X",
    "POST",
    "http://localhost:3000/worker/run"
  ],
  "presentation": {
    "reveal": "silent"
  },
  "runOptions": {
    "runOn": "folderOpen"
  }
}
```

Add this to `.vscode/tasks.json` in your project root.

### Run Worker via cURL (CLI)
```bash
curl -X POST http://localhost:3000/worker/run
```

### Run Worker via JavaScript/Node
```javascript
const response = await fetch('http://localhost:3000/worker/run', {
  method: 'POST'
});
const data = await response.json();
console.log(data);
```

## Task Details

### Task 1: Close Ended Jobs
- **When:** Daily at midnight
- **Action:** Updates all jobs with `status='open'` and `end_date <= NOW()` to `status='closed'` and sets `closed_at` timestamp
- **Log:** `[Worker] Closed job {jobUid}`

### Task 2: Process Unfilled Refunds
- **When:** Daily at midnight
- **Action:** Processes pending refunds from `unfilled_refunds` table where `issued_at IS NULL` and sets `issued_at` timestamp
- **Checks:**
  - Amount to refund must be > 0
  - `stripe_charge_id` must exist
  - `stripe_refund_id` must not already exist
- **On Success:** Sets `stripe_refund_id` and `issued_at = NOW()`
- **Error Handling:** Logs failures per refund row without stopping the process
- **Log:** `[Worker] Refunded {amount} for job {jobUid}`

## Configuration

### Environment Variables
```env
PORT=3000
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_USER=nullandvoid
POSTGRES_PASSWORD=Timecube420
POSTGRES_DB=void
STRIPE_SECRET_KEY=sk_...
```

### Logging Control
Toggle logging in `server.js`:
```javascript
const __wantLogs = true;  // Set to false to disable all logs
```

## Output on Server Start
```
API running on port 3000
[Worker] Daily worker started
[Tasks]
   1 : Close ended jobs [1/24hr, 00:01.00]
   2 : Issue refunds    [1/24hr, 00:00.00]
[Logging] true
```

## Error Handling
- Worker continues processing even if individual refunds fail
- All errors are logged with context (row UID, job UID, error message)
- Missing `stripe_charge_id` records are skipped with a warning log
- Database and Stripe errors are caught and reported per task