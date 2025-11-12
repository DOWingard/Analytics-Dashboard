# The Analytics Portion of the DB

This db logs basic backend information for analytics 

# Analytics Tables and Triggers

---

## `platform_analytics`

Tracks daily platform-level metrics and user activity statistics.

* Fields:

```
date (date, PK)
total_users (int)               -- total users in 'users' table
total_artists (int)             -- total users with user_type='artist'
total_influencers (int)         -- total users with user_type='influencer'
active_users_daily (int)        -- users active in last 24 hours
jobs_created (int)              -- total jobs created
jobs_closed (int)               -- total jobs with closed_at NOT NULL
influencers_paid (int)          -- total influencer_payouts
full_job_rate (numeric(5,4))   -- fraction of closed jobs where claim_count >= max_slots
current_open_jobs (int)         -- total jobs with closed_at IS NULL
```

---

## `financial_analytics`

Tracks daily financial metrics including payouts, refunds, and revenue.

* Fields:

```
date (date, PK)
total_payouts (numeric)          -- sum of influencer_payouts.amount
payouts_count (int)              -- total influencer_payouts entries
total_refunds (numeric)          -- sum of unfilled_refunds.refunded
refunds_count (int)              -- total unfilled_refunds entries
total_paid_for_campaigns (numeric) -- sum of all campaign budgets
net_revenue (numeric)            -- total_paid_for_campaigns - total_refunds - total_payouts
largest_single_payout (numeric)  -- largest influencer_payouts.amount
largest_single_refund (numeric)  -- largest unfilled_refunds.refunded
```


