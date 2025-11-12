# Backend Database Breakdown

The PostgreSQL backend is in a local container that has an exposable SSH port.

---

## Overview

```
* Artist         --> | Creates campaign                   | --> Job[Jobs Table]
* Influencer     --> | Claims job                         | --> Influencer_Job[influencer_jobs Table]
* Influencer_Job --> | Trigger trg_create_escrow_on_content_done | --> Escrow[Escrow Transactions]
* Escrow         --> | Trigger on INSERT                  | --> Event1[Escrow Events: "claimed"]
* Escrow         --> | Trigger on status update           | --> Event2[Escrow Events: "released"]
* Escrow         --> | Trigger on release/payment         | --> Event3[Escrow Events: "influencer_paid"]
* Jobs           --> | Trigger on closed_at               | --> unfilled_refunds (if claim_count < max_slots)
* unfilled_refunds --> | Trigger on issued_at             | --> escrow_events ('refund')
* influencer_jobs --> | Trigger on closed_at               | --> influencer_payouts
* influencer_jobs --> | Trigger on closed_at (unapproved content) | --> influencer_logs
* Jobs/escrow/unfilled_refunds/escrow_transactions
                 --> | Triggers prevent modifications after closed/released/refund issued | system_logs
* users          --> | Trigger before UPDATE on wallet    | system_logs (prevents wallet <0)
```

*Not actually an escrow system, only named for logging purposes*

---

See [ANALYTICS.md](___ANALYTICS.md) for the analytics backend

## Tables

### `users`

Represents all users: artists and influencers.

* Fields:

```
uid (text, Firebase UID), email, password, display_name, phone_number, bio, created_at, socials, payment_methods, user_type, wallet
```

* Trigger:

  * `prevent_negative_wallet()` → fires BEFORE UPDATE on `wallet`

    * Prevents `wallet` from being set below 0.
    * Logs into `system_logs` if prevented, including:

      * `source_uid` = user `uid`
      * `data` (jsonb) with attempted_value, previous_value, timestamp, email, user_type
    * Implemented as a PL/pgSQL function:

```sql
CREATE OR REPLACE FUNCTION prevent_negative_wallet()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.wallet < 0 THEN
        INSERT INTO system_logs (source_uid, data)
        VALUES (
            NEW.uid,
            jsonb_build_object(
                'action', 'prevent_negative_wallet',
                'attempted_value', NEW.wallet,
                'previous_value', OLD.wallet,
                'timestamp', now(),
                'user_email', NEW.email,
                'user_type', NEW.user_type
            )
        );
        NEW.wallet := OLD.wallet;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_negative_wallet
BEFORE UPDATE OF wallet ON users
FOR EACH ROW
EXECUTE FUNCTION prevent_negative_wallet();
```

This trigger ensures no wallet can go below 0 and logs the attempted violation in `system_logs`.

---

### `jobs`

Campaigns created by artists.

* Fields:

```
uid, title, description, budget, influencer_slots, influence_min, influence_max,
location, genre, creator_uid, status, created_at, closed_at, max_slots,
claim_count, influencers_done, all_content_ready, end_date, stripe_charge_id
```

* Triggers:

  * `jobs_closed_at_logging`
  * `jobs_set_max_slots`
  * `trg_check_influencers_done`
  * `trg_close_influencer_jobs`
  * `trg_create_unfilled_refund`
  * `trg_prevent_updates_after_closed`
  * `trg_reset_all_content_ready`
  * `trg_set_all_content_ready`
  * `update_status_on_close`

---

### `joblogs`

Tracks job-related events.

* Fields:

```
uid, job_uid, description, log (jsonb), created_at
```

---

### `influencer_jobs`

Tracks influencer claims.

* Fields:

```
uid, user_uid, job_uid, assigned_at, closed_at, content_done_at, content_approved_at, amount
```

* Triggers:

  * `trg_create_escrow_on_claim`
  * `trg_prevent_updates_after_closed`
  * `trg_create_influencer_payout`
  * `trg_log_unapproved_closure` (new addition)

---

### `influencer_payouts`

Tracks payouts to influencers after job completion.

* Fields:

```
uid (uuid, PK, default gen_random_uuid()), user_uid (text), job_uid (uuid), amount (numeric), genre (text), issued_at (timestamp), payed_at (timestamp, nullable)
```

* Trigger:

  * `trg_influencer_payout`

---

### `influencer_logs`

Tracks unapproved content closure events.

* Fields:

```
uid (uuid, PK, default gen_random_uuid())
user_uid (text, NOT NULL)
job_uid (uuid, NOT NULL)
description (text)
log (jsonb)
created_at (timestamp with time zone, default now())
```

* Trigger:

  * `trg_log_unapproved_closure` → fires AFTER UPDATE on `influencer_jobs` when `closed_at` is newly set, `content_done_at` exists, and `content_approved_at` is NULL.

* Action: inserts a record into `influencer_logs` with JSONB details including `closed_at`, `content_done_at`, `amount`.

---

### `claims`

Tracks influencers claiming jobs.

* Fields:

```
id, job_id, influencer_id, claimed_at
```

* Trigger:

  * `trg_create_escrow_on_claim`

---

### `escrow_transactions`

Tracks payments between buyer (artist) and seller (influencer)

* Fields:

```
escrow_uid, buyer_uid, seller_uid, payment_amount, payment_time, escrow_released_time, status
```

* Triggers:

  * `escrow_claim_trigger`
  * `escrow_released_trigger`
  * `trg_prevent_modifications_after_released`

---

### `escrow_events`

Logs events related to escrow.

* Fields:

```
event_uid, escrow_uid, event_type, event_details, created_at
```

---

### `unfilled_refunds`

Tracks refunds for unclaimed influencer slots

* Fields:

```
uid, user_uid, job_uid, max_slots, claimed_slots, budget, refunded, issued_at, created_at
```

* Triggers:

  * `log_refund_to_escrow_events`
  * `prevent_modifications_after_refund_issued`

---

### `system_logs`

Stores logs of blocked actions for auditing, including wallet prevention.

* Fields:

```
uid, source_uid, log_time (default now()), data (jsonb)
```

* Example JSON:

```json
{
  "table": "users",
  "action": "prevent_negative_wallet",
  "attempted_at": "2025-11-07T10:00:00Z",
  "message": "Attempted wallet update below 0 prevented",
  "old_data": { "wallet": 50.00 },
  "attempted_value": -20.00,
  "user_email": "example@mail.com",
  "user_type": "influencer"
}
```

---

### `platform_analytics`

Tracks daily platform-level metrics and user activity statistics.

* Fields:

```
date (date, PK), total_users, total_artists, total_influencers, active_users_daily,
jobs_created, jobs_closed, total_influencer_claims, system_events_logged, escrow_events_logged
```

* Description: Records aggregated metrics such as daily user counts, job creation/closure volumes, claim activity, and system event counts for analytics and reporting purposes.

---

### `financial_analytics`

Tracks daily financial metrics including payouts, refunds, and revenue.

* Fields:

```
date (date, PK), total_payouts (numeric), payouts_count, total_refunds (numeric),
refunds_count, platform_fees (numeric), net_revenue (numeric),
largest_single_payout (numeric), largest_single_refund (numeric)
```

* Description: Records daily financial transactions and metrics including total payouts to influencers, refunds issued, platform fees collected, net revenue calculations, and tracks the largest individual payout and refund for the day.

---

## Trigger Functions

### Modification/Deletion Prevention

* `prevent_modifications_after_closed()`
* `prevent_delete_after_closed()`
* `prevent_modifications_after_released()`
* `prevent_modifications_after_refund_issued()`
* `prevent_negative_wallet()` → prevents wallet <0 and logs attempts

### Logging & Refunds

* `log_refund_to_escrow_events()`
* `jobs_closed_at_logging()`
* `trg_create_unfilled_refund()`

### Job Management

* `set_max_slots()`
* `log_influencers_done_limit()`
* `close_related_influencer_jobs()`
* `reset_all_content_ready()`
* `update_all_content_ready()`
* `set_job_status_closed()`

---

## Trigger Flow (Textual)

```
Artist ---> Job
                 \
Influencer ---> influencer_jobs (claim)
                 \
                  trg_create_escrow_on_claim
                        \
                         escrow_transactions
                         |
                         | escrow_claim_trigger
                         v
                   escrow_events ('claimed')

Escrow status updated ('released')
         |
         v
  escrow_released_trigger
         |
         +--> escrow_events ('released')
         +--> wallet update for influencer
         +--> escrow_events ('influencer_paid')

Job closed (closed_at set)
         |
         +--> trg_create_unfilled_refund -> unfilled_refunds
                  |
                  +--> log_refund_to_escrow_events -> escrow_events ('refund')
         +--> jobs_closed_at_logging -> joblogs
         +--> trg_prevent_updates_after_closed -> system_logs

influencer_jobs.closed_at set
         |
         +--> trg_influencer_payout -> influencer_payouts
         +--> trg_log_unapproved_closure -> influencer_logs

unfilled_refunds.issued_at set
         |
         +--> prevent_modifications_after_refund_issued -> system_logs

users.wallet update attempted <0
         |
         +--> prevent_negative_wallet() -> system_logs
```

---

## Example `system_logs` JSON

```json
{
  "table": "users",
  "action": "prevent_negative_wallet",
  "attempted_at": "2025-11-07T10:00:00Z",
  "message": "Attempted wallet update below 0 prevented",
  "old_data": { "wallet": 50.00 },
  "attempted_value": -20.00,
  "user_email": "example@mail.com",
  "user_type": "influencer"
}
```

---

# Analytics Tables

```sql
-- Platform Analytics Table
CREATE TABLE IF NOT EXISTS platform_analytics (
    date                date PRIMARY KEY,
    total_users         integer NOT NULL DEFAULT 0,
    total_artists       integer NOT NULL DEFAULT 0,
    total_influencers   integer NOT NULL DEFAULT 0,
    active_users_daily  integer NOT NULL DEFAULT 0,
    jobs_created        integer NOT NULL DEFAULT 0,
    jobs_closed         integer NOT NULL DEFAULT 0,
    total_influencer_claims integer NOT NULL DEFAULT 0,
    system_events_logged    integer NOT NULL DEFAULT 0,
    escrow_events_logged     integer NOT NULL DEFAULT 0
);

-- Financial Analytics Table
CREATE TABLE IF NOT EXISTS financial_analytics (
    date                   date PRIMARY KEY,
    total_payouts          numeric(12,2) NOT NULL DEFAULT 0.00,
    payouts_count          integer NOT NULL DEFAULT 0,
    total_refunds          numeric(12,2) NOT NULL DEFAULT 0.00,
    refunds_count          integer NOT NULL DEFAULT 0,
    platform_fees          numeric(12,2) NOT NULL DEFAULT 0.00,
    net_revenue            numeric(12,2) NOT NULL DEFAULT 0.00,
    largest_single_payout  numeric(12,2) NOT NULL DEFAULT 0.00,
    largest_single_refund  numeric(12,2) NOT NULL DEFAULT 0.00
);
```

---

# Useful Commands

## Safely clear all tables except users

```sql
CREATE OR REPLACE FUNCTION public.trg_create_unfilled_refund()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    -- Trigger only when closed_at is newly set and job still has unfilled slots
    IF NEW.closed_at IS NOT NULL AND NEW.influencers_done < NEW.max_slots THEN
        INSERT INTO unfilled_refunds (
            user_uid,
            job_uid,
            max_slots,
            claimed_slots,
            budget,
            refunded,
            stripe_charge_id
        )
        VALUES (
            NEW.creator_uid,
            NEW.uid,
            NEW.max_slots,
            NEW.influencers_done,
            NEW.budget,
            -- Refund calculation based on unapproved slots
            (NEW.budget / NEW.max_slots) * (NEW.max_slots - NEW.approved),
            NEW.stripe_charge_id
        );
    END IF;

    RETURN NEW;
END;
$function$;

```

## Without Users
```sql
TRUNCATE TABLE 
    claims,
    escrow_events,
    content_submissions,
    escrow_transactions,
    influencer_jobs,
    influencer_payouts,
    influencer_logs,
    joblogs,
    jobs,
    system_logs,
    unfilled_refunds
RESTART IDENTITY CASCADE;
```

## With Users
```sql
TRUNCATE TABLE 
    claims,
    escrow_events,
    content_submissions,
    escrow_transactions,
    influencer_jobs,
    influencer_payouts,
    influencer_logs,
    joblogs,
    jobs,
    system_logs,
    unfilled_refunds,
    users
RESTART IDENTITY CASCADE;
```