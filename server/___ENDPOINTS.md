# API Endpoints

## User Endpoints
* `POST /create-user` – Create a new user
  * Updates `last_active` timestamp on creation
* `POST /sign-in` – Sign in (with or without password)
  * Updates `last_active` timestamp on successful login
* `GET /users` – Get all users
* `GET /users/:uid` – Get a single user
  * Updates `last_active` timestamp for the requested user
* `PATCH /users/:uid` – Update user details
  * Updates `last_active` timestamp for the updated user
* `PATCH /users/:uid/wallet` – Adjust wallet balance by delta
  * Updates `last_active` timestamp for the user

## Job Endpoints
* `GET /jobs` – Get all jobs or filter by `?uid=` (creator)
  * Updates `last_active` timestamp if uid query parameter is provided
* `GET /jobs/:id` – Get job by ID
* `POST /jobs` – Create a new job (automatically charges creator via Stripe)
  * Updates `last_active` timestamp for the creator
* `POST /jobs/:id/claim` – Claim a job (influencer accepts)
  * Updates `last_active` timestamp for the influencer claiming the job
* `GET /influencer-jobs/user/:uid` – Get jobs claimed by a specific influencer
  * Updates `last_active` timestamp for the influencer
* `GET /influencer-jobs/job/:jobUid` – Get influencers who claimed a specific job
* `POST /influencer-jobs/approve` – Mark influencer content as approved (artist only)
  * Updates `last_active` timestamp for the artist approving content
* `POST /influencer-jobs/:claimUid/influencerComplete` – Mark influencer job as done
  * Updates `last_active` timestamp for the influencer completing the job
* `POST /jobs/:id/close` – Manually close a job and automatically create an unfilled refund if slots were unclaimed
  * Does not require user context, no `last_active` update

## Unfilled Refunds
* Created automatically when a job is closed (`POST /jobs/:id/close`)
* Tracks refunds for unclaimed influencer slots:
  * `uid` – Refund ID
  * `user_uid` – Creator being refunded
  * `job_uid` – Related job
  * `max_slots` – Total slots in job
  * `claimed_slots` – Slots claimed by influencers
  * `budget` – Total budget
  * `refunded` – Amount to refund
  * `issued_at` – Timestamp of refund creation

## Escrow Endpoints
* `POST /escrow` – Create an escrow transaction
  * Updates `last_active` timestamp for both buyer and seller
* `GET /escrow` – Get all escrow transactions
* `PATCH /escrow/:escrow_id/status` – Update escrow status
  * Optionally updates `last_active` if userId is provided in request body

## Stripe Endpoints
* `POST /stripe/create-customer` – Create Stripe customer for user
  * Updates `last_active` timestamp for the user
* `POST /stripe/add-payment-method` – Attach a payment method to a Stripe customer
  * Updates `last_active` timestamp for the user
* `POST /stripe/update-payment-method` – Update billing details for a payment method
  * Updates `last_active` timestamp for the user
* `POST /stripe/charge` – Charge a user via Stripe
  * Updates `last_active` timestamp for the user being charged
* `POST /stripe/refund` – Refund a paymentIntent (full or partial)
  * Does not require user context, no `last_active` update

### Stripe Connect Endpoints
* `POST /stripe/connect/create` – Create or fetch a Stripe Connect Express account for payouts
  * Updates `last_active` timestamp for the user
* `POST /stripe/connect/onboard` – Generate onboarding link for user to finish bank setup
  * Updates `last_active` timestamp for the user
* `POST /stripe/connect/payout` – Transfer funds from platform wallet → user's connected bank account
  * Updates `last_active` timestamp for the user initiating the payout
* `GET /stripe/complete` – Success page after Stripe onboarding completion

---

## Activity Tracking

All endpoints that identify a specific user automatically update that user's `last_active` timestamp to `NOW()`. This enables real-time activity monitoring and usage statistics without requiring changes to client wrapper implementations.

**User identification occurs through:**
- `uid` in URL path parameters (e.g., `/users/:uid`, `/influencer-jobs/user/:uid`)
- `uid` in query parameters (e.g., `/jobs?uid=...`)
- `uid` or `userId` or `userUid` in request body (e.g., POST requests with creator/influencer identifiers)

**Endpoints without automatic tracking:**
- System-level operations that don't target a specific user (e.g., `/GET /jobs/:id`, `/GET /escrow`)
- Endpoints that don't receive user context (e.g., `/stripe/refund`)