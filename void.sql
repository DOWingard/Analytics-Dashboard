--
-- PostgreSQL database dump
--

\restrict kZCmpCWcMyoLzI74dib81j8E2PSUswXzCM8dZkupagkftnRuAw4viSHVgXcZ1dE

-- Dumped from database version 15.14 (Debian 15.14-1.pgdg13+1)
-- Dumped by pg_dump version 15.14 (Debian 15.14-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: close_jobs_by_end_date(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.close_jobs_by_end_date() RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE jobs
    SET closed_at = NOW()
    WHERE closed_at IS NULL
      AND end_date <= CURRENT_DATE;
END;
$$;


ALTER FUNCTION public.close_jobs_by_end_date() OWNER TO nullandvoid;

--
-- Name: close_related_influencer_jobs(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.close_related_influencer_jobs() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only run when closed_at changes from NULL to a real timestamp
    IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN
        UPDATE public.influencer_jobs
        SET closed_at = NEW.closed_at
        WHERE job_uid = NEW.uid
          AND closed_at IS NULL; -- only update ones still open
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.close_related_influencer_jobs() OWNER TO nullandvoid;

--
-- Name: create_claim_on_influencer_job(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.create_claim_on_influencer_job() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Try to insert a claim for the new influencer_job
    INSERT INTO claims (job_id, influencer_id, claimed_at)
    VALUES (
        NEW.job_uid,
        NEW.user_uid,
        COALESCE(NEW.assigned_at, NOW())
    )
    ON CONFLICT (job_id, influencer_id) DO NOTHING; -- prevent duplicates

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_claim_on_influencer_job() OWNER TO nullandvoid;

--
-- Name: create_escrow_on_content_approved(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.create_escrow_on_content_approved() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    job_record RECORD;
BEGIN
    -- Only fire when content_approved_at is newly set
    IF NEW.content_approved_at IS NOT NULL AND OLD.content_approved_at IS NULL THEN

        -- Get job info
        SELECT creator_uid
        INTO job_record
        FROM jobs
        WHERE uid = NEW.job_uid;

        IF NOT FOUND THEN
            RAISE NOTICE 'Job % not found', NEW.job_uid;
            RETURN NEW;
        END IF;

        -- Insert escrow transaction
        INSERT INTO escrow_transactions(
            buyer_uid,
            seller_uid,
            payment_amount,
            status
        )
        VALUES (
            job_record.creator_uid,
            NEW.user_uid,
            NEW.amount,
            'pending'
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_escrow_on_content_approved() OWNER TO nullandvoid;

--
-- Name: create_escrow_on_content_done(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.create_escrow_on_content_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    job_record RECORD;
BEGIN
    -- Only fire when content_done_at is newly set
    IF NEW.content_done_at IS NOT NULL AND OLD.content_done_at IS NULL THEN

        -- Get job info
        SELECT creator_uid
        INTO job_record
        FROM jobs
        WHERE uid = NEW.job_uid;

        IF NOT FOUND THEN
            RAISE NOTICE 'Job % not found', NEW.job_uid;
            RETURN NEW;
        END IF;

        -- Insert escrow transaction
        INSERT INTO escrow_transactions(
            buyer_uid,
            seller_uid,
            payment_amount,
            status
        )
        VALUES (
            job_record.creator_uid,
            NEW.user_uid,
            NEW.amount,
            'pending'
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_escrow_on_content_done() OWNER TO nullandvoid;

--
-- Name: create_influencer_payout(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.create_influencer_payout() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.closed_at IS NOT NULL
       AND NEW.content_approved_at IS NOT NULL
       AND OLD.closed_at IS NULL THEN
        INSERT INTO influencer_payouts (
            user_uid,
            job_uid,
            amount,
            genre,
            issued_at,
            payed_at
        )
        SELECT
            NEW.user_uid,
            NEW.job_uid,
            NEW.amount,
            j.genre,
            NEW.closed_at,
            NULL
        FROM jobs j
        WHERE j.uid = NEW.job_uid;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_influencer_payout() OWNER TO nullandvoid;

--
-- Name: delete_related_content_submissions(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.delete_related_content_submissions() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM content_submissions
    WHERE influencer_uid = OLD.user_uid
      AND job_uid = OLD.job_uid;

    RETURN OLD;
END;
$$;


ALTER FUNCTION public.delete_related_content_submissions() OWNER TO nullandvoid;

--
-- Name: increment_influencers_done(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.increment_influencers_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only increment if content_done_at is newly set
    IF NEW.content_done_at IS NOT NULL AND OLD.content_done_at IS NULL THEN
        -- Increment influencers_done in the associated job
        UPDATE public.jobs
        SET influencers_done = COALESCE(influencers_done, 0) + 1
        WHERE uid = NEW.job_uid;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.increment_influencers_done() OWNER TO nullandvoid;

--
-- Name: log_escrow_content_done(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_escrow_content_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only fire when content_done_at is newly set
    IF NEW.content_done_at IS NOT NULL AND OLD.content_done_at IS NULL THEN
        INSERT INTO escrow_events (
            escrow_uid,
            event_type,
            event_details,
            created_at
        )
        VALUES (
            NEW.uid,  -- escrow transaction ID
            'content_submitted',  -- updated event type
            'Content submitted by influencer ' || NEW.seller_uid,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_escrow_content_done() OWNER TO nullandvoid;

--
-- Name: log_escrow_released(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_escrow_released() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only trigger if escrow_released_time was updated
    IF NEW.escrow_released_time IS DISTINCT FROM OLD.escrow_released_time THEN
        -- Check that escrow_uid exists in escrow_transactions
        IF EXISTS (
            SELECT 1 FROM escrow_transactions
            WHERE escrow_uid = NEW.escrow_uid
        ) THEN
            INSERT INTO escrow_events (
                escrow_uid,
                event_type,
                event_details
            )
            VALUES (
                NEW.escrow_uid,
                'Influencer_paid',
                FORMAT(
                    'Job %s: payment from %s to %s released and closed.',
                    NEW.escrow_uid,
                    NEW.buyer_uid,
                    NEW.seller_uid
                )
            );
        ELSE
            RAISE NOTICE '⚠️ Skipping escrow_event insert: escrow_uid % not found in escrow_transactions', NEW.escrow_uid;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_escrow_released() OWNER TO nullandvoid;

--
-- Name: log_influencer_job_deletion(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_influencer_job_deletion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO influencer_logs (
    user_uid,
    job_uid,
    description,
    log
  ) VALUES (
    OLD.user_uid,
    OLD.job_uid,
    'Influencer removed from job',
    jsonb_build_object(
      'event', 'influencer_job_deleted',
      'timestamp', NOW(),
      'influencer_uid', OLD.user_uid,
      'job_uid', OLD.job_uid,
      'deleted_record', jsonb_build_object(
        'influencer_jobs_uid', OLD.uid,
        'assigned_at', OLD.assigned_at,
        'content_done_at', OLD.content_done_at,
        'content_approved_at', OLD.content_approved_at,
        'amount', OLD.amount,
        'closed_at', OLD.closed_at
      ),
      'reason', 'Artist removed influencer from campaign',
      'database_action', 'DELETE'
    )
  );
  RETURN OLD;
END;
$$;


ALTER FUNCTION public.log_influencer_job_deletion() OWNER TO nullandvoid;

--
-- Name: log_influencers_done_limit(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_influencers_done_limit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the update would exceed max_slots
    IF NEW.influencers_done > NEW.max_slots THEN
        -- Insert a log into system_logs
        INSERT INTO system_logs(source_uid, data)
        VALUES (
            NEW.uid,
            jsonb_build_object(
                'issue', 'influencers_done exceeds max_slots',
                'table', 'jobs',
                'attempted_influencers_done', NEW.influencers_done,
                'max_slots', NEW.max_slots,
                'updated_columns', TG_ARGV[0]  -- optional info about which column triggered
            )
        );

        -- Prevent the update
        RAISE EXCEPTION 'Cannot set influencers_done > max_slots';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_influencers_done_limit() OWNER TO nullandvoid;

--
-- Name: log_job_issues(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_job_issues() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    log_description TEXT[] := '{}'; -- safer initialization
    log_data JSONB;
BEGIN
    -- Only fire when closed_at is newly set
    IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN

        log_data := jsonb_build_object(
            'genre', NEW.genre,
            'creator_uid', NEW.creator_uid,
            'created_at', NEW.created_at,
            'closed_at', NEW.closed_at,
            'max_slots', NEW.max_slots,
            'claim_count', NEW.claim_count,
            'influencers_done', NEW.influencers_done,
            'all_content_ready', NEW.all_content_ready,
            'end_date', NEW.end_date
        );

        -- Most important: influencers submitted work but all_content_ready is null
        IF NEW.all_content_ready IS NULL AND NEW.influencers_done > 0 THEN
            log_description := array_append(log_description, 'Closed on influencers who submitted work without approving the work');
        END IF;

        -- Closed within a day of creation
        IF NEW.closed_at <= NEW.created_at + interval '1 day' THEN
            log_description := array_append(log_description, 'Job closed within a day of creation');
        END IF;

        -- influencers_done < claim_count
        IF NEW.influencers_done < NEW.claim_count THEN
            log_description := array_append(log_description, 'Not all claimed slots were completed by influencers');
        END IF;

        -- all_content_ready not set
        IF NEW.all_content_ready IS NULL THEN
            log_description := array_append(log_description, 'Job closed before all content was ready');
        END IF;

        -- Insert a single log row only if there are any issues
        IF array_length(log_description, 1) > 0 THEN
            INSERT INTO jobLogs(job_uid, description, log)
            VALUES (NEW.uid, array_to_string(log_description, '; '), log_data);
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_job_issues() OWNER TO nullandvoid;

--
-- Name: log_unapproved_closure(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.log_unapproved_closure() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    log_description TEXT[];
    log_data JSONB;
BEGIN
    -- Only fire when closed_at is newly set
    IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN

        log_data := jsonb_build_object(
            'closed_at', NEW.closed_at,
            'content_done_at', NEW.content_done_at,
            'content_approved_at', NEW.content_approved_at,
            'amount', NEW.amount
        );

        log_description := ARRAY[]::TEXT[];

        -- Log if influencers submitted work but it was not approved
        IF NEW.content_done_at IS NOT NULL AND NEW.content_approved_at IS NULL THEN
            log_description := log_description || ARRAY['Client CLOSED WITHOUT APPROVING submitted content'];
        END IF;

        -- Insert log if there are issues
        IF array_length(log_description, 1) IS NOT NULL THEN
            INSERT INTO influencer_logs(user_uid, job_uid, description, log, created_at)
            VALUES (NEW.user_uid, NEW.job_uid, array_to_string(log_description, '; '), log_data, now());
        END IF;

    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_unapproved_closure() OWNER TO nullandvoid;

--
-- Name: populate_financial_analytics(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.populate_financial_analytics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    total_payout numeric(12,2);
    payout_count integer;
    total_refund numeric(12,2);
    refund_count integer;
    largest_payout numeric(12,2);
    largest_refund numeric(12,2);
BEGIN
    -- Payout metrics
    SELECT 
        COALESCE(SUM(amount),0),
        COUNT(*),
        COALESCE(MAX(amount),0)
    INTO total_payout, payout_count, largest_payout
    FROM influencer_payouts;

    NEW.total_payouts := total_payout;
    NEW.payouts_count := payout_count;
    NEW.largest_single_payout := largest_payout;

    -- Refund metrics (using 'refunded' column)
    SELECT 
        COALESCE(SUM(refunded),0),
        COUNT(*),
        COALESCE(MAX(refunded),0)
    INTO total_refund, refund_count, largest_refund
    FROM unfilled_refunds;

    NEW.total_refunds := total_refund;
    NEW.refunds_count := refund_count;
    NEW.largest_single_refund := largest_refund;

    -- Total paid for campaigns
    NEW.total_paid_for_campaigns := total_payout + total_refund;

    -- Net revenue
    NEW.net_revenue := NEW.total_paid_for_campaigns - total_refund - total_payout;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.populate_financial_analytics() OWNER TO nullandvoid;

--
-- Name: populate_platform_analytics(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.populate_platform_analytics() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    closed_count integer;
    full_count integer;
BEGIN
    -- Existing metrics
    NEW.total_users := (SELECT COUNT(*) FROM users);
    NEW.total_artists := (SELECT COUNT(*) FROM users WHERE user_type = 'artist');
    NEW.total_influencers := (SELECT COUNT(*) FROM users WHERE user_type = 'influencer');
    NEW.active_users_daily := (SELECT COUNT(*) FROM users WHERE last_active >= NOW() - INTERVAL '24 hours');
    NEW.jobs_created := (SELECT COUNT(*) FROM jobs);
    NEW.jobs_closed := (SELECT COUNT(*) FROM jobs WHERE closed_at IS NOT NULL);
    NEW.influencers_paid := (SELECT COUNT(*) FROM influencer_payouts);

    -- Full job rate calculation
    SELECT COUNT(*) 
    INTO closed_count
    FROM jobs
    WHERE closed_at IS NOT NULL;

    SELECT COUNT(*) 
    INTO full_count
    FROM jobs
    WHERE closed_at IS NOT NULL AND claim_count >= max_slots;

    IF closed_count = 0 THEN
        NEW.full_job_rate := 0;
    ELSE
        NEW.full_job_rate := ROUND(full_count::numeric / closed_count::numeric, 4);
    END IF;

    -- Current open jobs
    NEW.current_open_jobs := (SELECT COUNT(*) FROM jobs WHERE closed_at IS NULL);

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.populate_platform_analytics() OWNER TO nullandvoid;

--
-- Name: prevent_invalid_refund(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.prevent_invalid_refund() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Correct per-slot refund calculation for unfilled_refunds table
    IF NEW.refunded <> (NEW.budget / NEW.max_slots) * (NEW.max_slots - NEW.approved_slots) THEN
        RAISE EXCEPTION 'Refund value mismatch: expected %, got %',
            (NEW.budget / NEW.max_slots) * (NEW.max_slots - NEW.approved_slots),
            NEW.refunded;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_invalid_refund() OWNER TO nullandvoid;

--
-- Name: prevent_modifications_after_closed(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.prevent_modifications_after_closed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Check if refund has been issued
  IF OLD.stripe_refund_id IS NOT NULL THEN
    -- Log the attempted modification
    INSERT INTO public.system_logs (source_uid, data)
    VALUES (
      OLD.uid,
      jsonb_build_object(
        'table', TG_TABLE_NAME,
        'action', TG_OP,
        'attempted_at', now(),
        'message', 'Attempted modification blocked because refund has been issued',
        'old_data', to_jsonb(OLD)
      )
    );

    -- Prevent the update
    RAISE EXCEPTION 'Cannot modify record in table "%" (id=%) because refund has been issued.',
      TG_TABLE_NAME, OLD.uid;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_modifications_after_closed() OWNER TO nullandvoid;

--
-- Name: prevent_modifications_after_refund_issued(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.prevent_modifications_after_refund_issued() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Block updates if there is a Stripe charge but no refund yet
  IF OLD.stripe_refund_id IS NULL AND OLD.stripe_charge_id IS NOT NULL THEN
    -- Log the attempted modification
    INSERT INTO public.system_logs (source_uid, data)
    VALUES (
      OLD.uid,
      jsonb_build_object(
        'table', TG_TABLE_NAME,
        'action', TG_OP,
        'attempted_at', now(),
        'message', 'Attempted modification blocked because Stripe charge exists but refund has not been issued',
        'old_data', to_jsonb(OLD)
      )
    );

    -- Prevent the update
    RAISE EXCEPTION 'Cannot modify record in table "%" (id=%) because Stripe charge exists but refund has not been issued.',
      TG_TABLE_NAME, OLD.uid;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_modifications_after_refund_issued() OWNER TO nullandvoid;

--
-- Name: prevent_modifications_after_released(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.prevent_modifications_after_released() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.escrow_released_time IS NOT NULL THEN
    -- Insert a descriptive log into system_logs
    INSERT INTO public.system_logs (source_uid, data)
    VALUES (
      OLD.escrow_uid,
      jsonb_build_object(
        'table', TG_TABLE_NAME,
        'action', TG_OP,
        'attempted_at', now(),
        'message', 'Attempted modification blocked because escrow has been released',
        'old_data', to_jsonb(OLD)
      )
    );

    -- Prevent modification
    RAISE EXCEPTION 'Cannot modify record in table "%" (id=%) because escrow has been released.',
      TG_TABLE_NAME, OLD.escrow_uid;
  END IF;

  RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_modifications_after_released() OWNER TO nullandvoid;

--
-- Name: prevent_negative_wallet(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.prevent_negative_wallet() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if the new wallet value is less than 0
    IF NEW.wallet < 0 THEN
        -- Log the attempted negative update into system_logs
        INSERT INTO system_logs (source_uid, data)
        VALUES (
            NEW.uid,  -- user performing the update
            jsonb_build_object(
                'action', 'prevent_negative_wallet',
                'attempted_value', NEW.wallet,
                'previous_value', OLD.wallet,
                'timestamp', now(),
                'user_email', NEW.email,
                'user_type', NEW.user_type
            )
        );
        
        -- Prevent the update by keeping the old wallet value
        NEW.wallet := OLD.wallet;
    END IF;

    -- Allow the update to proceed
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.prevent_negative_wallet() OWNER TO nullandvoid;

--
-- Name: release_escrow_on_influencer_close(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.release_escrow_on_influencer_close() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    buyer_id text;
BEGIN
    -- Only run when closed_at changes from NULL to a timestamp
    IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN
        -- 1️⃣ Find the job creator (buyer)
        SELECT creator_uid INTO buyer_id
        FROM public.jobs
        WHERE uid = NEW.job_uid;

        -- 2️⃣ Update escrow transactions for this buyer/seller pair
        UPDATE public.escrow_transactions
        SET 
            escrow_released_time = NEW.closed_at,
            status = 'released'
        WHERE buyer_uid = buyer_id
          AND seller_uid = NEW.user_uid
          AND escrow_released_time IS NULL;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.release_escrow_on_influencer_close() OWNER TO nullandvoid;

--
-- Name: reset_all_content_ready(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.reset_all_content_ready() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- If all_content_ready was set, but claim_count > influencers_done, reset it
    IF NEW.all_content_ready IS NOT NULL AND NEW.claim_count > NEW.influencers_done THEN
        UPDATE public.jobs
        SET all_content_ready = NULL
        WHERE uid = NEW.uid;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.reset_all_content_ready() OWNER TO nullandvoid;

--
-- Name: set_amount_zero_if_closed_without_content(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.set_amount_zero_if_closed_without_content() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act if closed_at is being set and content_done_at is NULL
    IF NEW.closed_at IS NOT NULL AND NEW.content_done_at IS NULL THEN
        NEW.amount := 0;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_amount_zero_if_closed_without_content() OWNER TO nullandvoid;

--
-- Name: set_job_status_closed(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.set_job_status_closed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only update status if closed_at is newly set
    IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN
        NEW.status := 'closed';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_job_status_closed() OWNER TO nullandvoid;

--
-- Name: set_max_slots(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.set_max_slots() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.max_slots := NEW.influencer_slots;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.set_max_slots() OWNER TO nullandvoid;

--
-- Name: trg_create_unfilled_refund(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_create_unfilled_refund() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Trigger only when closed_at is newly set and job still has unfilled slots
    IF NEW.closed_at IS NOT NULL AND NEW.approved < NEW.max_slots THEN
        INSERT INTO unfilled_refunds (
            user_uid,
            job_uid,
            max_slots,
            approved_slots,
            budget,
            refunded,
            stripe_charge_id
        )
        VALUES (
            NEW.creator_uid,
            NEW.uid,
            NEW.max_slots,
            NEW.approved,  -- use approved from jobs table
            NEW.budget,
            -- Refund calculation based on unapproved slots
            (NEW.budget / NEW.max_slots) * (NEW.max_slots - NEW.approved),
            NEW.stripe_charge_id
        );
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_create_unfilled_refund() OWNER TO nullandvoid;

--
-- Name: trg_decrement_influencers_done(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_decrement_influencers_done() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act if content_done_at changes from a value to NULL
    IF OLD.content_done_at IS NOT NULL AND NEW.content_done_at IS NULL THEN
        UPDATE jobs
        SET influencers_done = GREATEST(influencers_done - 1, 0)
        WHERE uid = NEW.job_uid;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_decrement_influencers_done() OWNER TO nullandvoid;

--
-- Name: trg_reset_all_approved_at(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_reset_all_approved_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check the conditions
    IF NEW.influencers_done = 0 OR NEW.approved < NEW.influencers_done THEN
        NEW.all_approved_at := NULL;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_reset_all_approved_at() OWNER TO nullandvoid;

--
-- Name: trg_reset_influencer_job_on_reject(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_reset_influencer_job_on_reject() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act if rejected_at is newly set
    IF NEW.rejected_at IS NOT NULL AND OLD.rejected_at IS NULL THEN
        UPDATE influencer_jobs
        SET content_done_at = NULL
        WHERE job_uid = NEW.job_uid
          AND user_uid = NEW.influencer_uid;  -- corrected column name
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_reset_influencer_job_on_reject() OWNER TO nullandvoid;

--
-- Name: trg_update_all_approved_at(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_update_all_approved_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- If approved equals influencers_done, set all_approved_at to current timestamp
    IF NEW.approved = NEW.influencers_done THEN
        NEW.all_approved_at := now();
    ELSE
        -- Otherwise, reset to NULL
        NEW.all_approved_at := NULL;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_update_all_approved_at() OWNER TO nullandvoid;

--
-- Name: trg_update_influencer_job_on_approve(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.trg_update_influencer_job_on_approve() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only act if approved_at is newly set
    IF NEW.approved_at IS NOT NULL AND (OLD.approved_at IS NULL OR OLD.approved_at <> NEW.approved_at) THEN
        UPDATE influencer_jobs
        SET content_approved_at = NEW.approved_at
        WHERE job_uid = NEW.job_uid
          AND user_uid = NEW.influencer_uid;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_update_influencer_job_on_approve() OWNER TO nullandvoid;

--
-- Name: update_all_content_ready(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.update_all_content_ready() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only set all_content_ready if influencers_done = claim_count AND it's not set yet
    IF NEW.influencers_done = NEW.claim_count AND NEW.all_content_ready IS NULL THEN
        UPDATE public.jobs
        SET all_content_ready = NOW()
        WHERE uid = NEW.uid;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_all_content_ready() OWNER TO nullandvoid;

--
-- Name: update_influencer_wallet(); Type: FUNCTION; Schema: public; Owner: nullandvoid
--

CREATE FUNCTION public.update_influencer_wallet() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Add the payout amount to the user's wallet
    UPDATE users
    SET wallet = COALESCE(wallet, 0) + NEW.amount
    WHERE uid = NEW.user_uid;

    -- Mark this payout as paid
    UPDATE influencer_payouts
    SET payed_at = NOW()
    WHERE uid = NEW.uid;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_influencer_wallet() OWNER TO nullandvoid;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: claims; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    job_id uuid NOT NULL,
    influencer_id text NOT NULL,
    claimed_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.claims OWNER TO nullandvoid;

--
-- Name: content_submissions; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.content_submissions (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    job_uid uuid NOT NULL,
    influencer_uid text NOT NULL,
    media_type text NOT NULL,
    media_url text NOT NULL,
    file_name text,
    file_size bigint,
    mime_type text,
    duration_sec numeric,
    resolution text,
    submitted_at timestamp without time zone DEFAULT now(),
    approved_at timestamp without time zone,
    rejected_at timestamp without time zone,
    CONSTRAINT content_submissions_media_type_check CHECK ((media_type = ANY (ARRAY['image'::text, 'video'::text])))
);


ALTER TABLE public.content_submissions OWNER TO nullandvoid;

--
-- Name: escrow_events; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.escrow_events (
    event_uid integer NOT NULL,
    escrow_uid uuid NOT NULL,
    event_type character varying(50) NOT NULL,
    event_details text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.escrow_events OWNER TO nullandvoid;

--
-- Name: escrow_events_event_id_seq; Type: SEQUENCE; Schema: public; Owner: nullandvoid
--

CREATE SEQUENCE public.escrow_events_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.escrow_events_event_id_seq OWNER TO nullandvoid;

--
-- Name: escrow_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: nullandvoid
--

ALTER SEQUENCE public.escrow_events_event_id_seq OWNED BY public.escrow_events.event_uid;


--
-- Name: escrow_transactions; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.escrow_transactions (
    escrow_uid uuid DEFAULT gen_random_uuid() NOT NULL,
    buyer_uid text NOT NULL,
    seller_uid text NOT NULL,
    payment_amount numeric(12,2) NOT NULL,
    payment_time timestamp without time zone DEFAULT now(),
    escrow_released_time timestamp without time zone,
    status character varying(20) DEFAULT 'pending'::character varying
);


ALTER TABLE public.escrow_transactions OWNER TO nullandvoid;

--
-- Name: financial_analytics; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.financial_analytics (
    date date NOT NULL,
    total_payouts numeric(12,2) DEFAULT 0.00 NOT NULL,
    payouts_count integer DEFAULT 0 NOT NULL,
    total_refunds numeric(12,2) DEFAULT 0.00 NOT NULL,
    refunds_count integer DEFAULT 0 NOT NULL,
    total_paid_for_campaigns numeric(12,2) DEFAULT 0.00 NOT NULL,
    net_revenue numeric(12,2) DEFAULT 0.00 NOT NULL,
    largest_single_payout numeric(12,2) DEFAULT 0.00 NOT NULL,
    largest_single_refund numeric(12,2) DEFAULT 0.00 NOT NULL
);


ALTER TABLE public.financial_analytics OWNER TO nullandvoid;

--
-- Name: influencer_jobs; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.influencer_jobs (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_uid text NOT NULL,
    job_uid uuid NOT NULL,
    assigned_at timestamp without time zone DEFAULT now(),
    closed_at timestamp without time zone,
    amount numeric,
    content_done_at timestamp without time zone,
    content_approved_at timestamp without time zone
);


ALTER TABLE public.influencer_jobs OWNER TO nullandvoid;

--
-- Name: influencer_logs; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.influencer_logs (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_uid text NOT NULL,
    job_uid uuid NOT NULL,
    description text,
    log jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.influencer_logs OWNER TO nullandvoid;

--
-- Name: influencer_payouts; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.influencer_payouts (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_uid text NOT NULL,
    job_uid uuid NOT NULL,
    amount numeric NOT NULL,
    genre text,
    issued_at timestamp without time zone DEFAULT now() NOT NULL,
    payed_at timestamp without time zone
);


ALTER TABLE public.influencer_payouts OWNER TO nullandvoid;

--
-- Name: joblogs; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.joblogs (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    job_uid uuid NOT NULL,
    description text,
    log jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.joblogs OWNER TO nullandvoid;

--
-- Name: jobs; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.jobs (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    budget numeric NOT NULL,
    influencer_slots integer NOT NULL,
    influence_min integer NOT NULL,
    influence_max integer NOT NULL,
    location text NOT NULL,
    genre text NOT NULL,
    creator_uid text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    closed_at timestamp without time zone,
    max_slots integer DEFAULT 0 NOT NULL,
    claim_count integer GENERATED ALWAYS AS ((max_slots - influencer_slots)) STORED,
    influencers_done integer DEFAULT 0,
    all_content_ready timestamp without time zone,
    end_date date NOT NULL,
    stripe_charge_id text NOT NULL,
    all_approved_at timestamp without time zone,
    approved integer DEFAULT 0 NOT NULL,
    CONSTRAINT jobs_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);


ALTER TABLE public.jobs OWNER TO nullandvoid;

--
-- Name: platform_analytics; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.platform_analytics (
    date date NOT NULL,
    total_users integer DEFAULT 0 NOT NULL,
    total_artists integer DEFAULT 0 NOT NULL,
    total_influencers integer DEFAULT 0 NOT NULL,
    active_users_daily integer DEFAULT 0 NOT NULL,
    jobs_created integer DEFAULT 0 NOT NULL,
    jobs_closed integer DEFAULT 0 NOT NULL,
    influencers_paid integer DEFAULT 0 NOT NULL,
    full_job_rate numeric(5,4) DEFAULT 0.0 NOT NULL,
    current_open_jobs integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.platform_analytics OWNER TO nullandvoid;

--
-- Name: system_logs; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.system_logs (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    source_uid uuid,
    log_time timestamp with time zone DEFAULT now(),
    data jsonb
);


ALTER TABLE public.system_logs OWNER TO nullandvoid;

--
-- Name: unfilled_refunds; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.unfilled_refunds (
    uid uuid DEFAULT gen_random_uuid() NOT NULL,
    user_uid text NOT NULL,
    job_uid uuid NOT NULL,
    max_slots integer NOT NULL,
    approved_slots integer NOT NULL,
    budget numeric(12,2) NOT NULL,
    refunded numeric(12,2) DEFAULT 0 NOT NULL,
    issued_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT now(),
    stripe_refund_id text,
    stripe_charge_id text
);


ALTER TABLE public.unfilled_refunds OWNER TO nullandvoid;

--
-- Name: users; Type: TABLE; Schema: public; Owner: nullandvoid
--

CREATE TABLE public.users (
    uid text NOT NULL,
    email character varying(255) NOT NULL,
    password text,
    display_name character varying(255),
    phone_number character varying(50),
    bio text,
    created_at timestamp without time zone DEFAULT now(),
    socials jsonb DEFAULT '{}'::jsonb,
    payment_methods jsonb DEFAULT '{}'::jsonb,
    user_type character varying(20) NOT NULL,
    wallet numeric(9,2) DEFAULT 0.00,
    last_active timestamp without time zone DEFAULT now() NOT NULL,
    location text,
    is_valid boolean DEFAULT false NOT NULL
);


ALTER TABLE public.users OWNER TO nullandvoid;

--
-- Name: escrow_events event_uid; Type: DEFAULT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.escrow_events ALTER COLUMN event_uid SET DEFAULT nextval('public.escrow_events_event_id_seq'::regclass);


--
-- Data for Name: claims; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.claims (id, job_id, influencer_id, claimed_at) FROM stdin;
fb2f576f-4394-4182-a019-25be96d50b3a	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 04:35:56.685195
a0d8b2c6-a815-4db3-b78c-1fb1dd30bfce	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	ziaYVl5tmybTTtKYintWOh132Nu1	2025-11-11 04:36:50.018399
a5e1e704-7e56-4793-bfb9-44ea6697b4bc	aca16e5d-f074-4410-b89a-6da5a36d9d0e	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 04:39:52.980614
f00bdd21-ab6a-495f-bb91-262ad0a230d1	aca16e5d-f074-4410-b89a-6da5a36d9d0e	ziaYVl5tmybTTtKYintWOh132Nu1	2025-11-11 04:43:59.636764
dc043548-2422-4622-9b9c-5bdf0eef5ebe	959e130a-79df-4263-a343-377633591ccd	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 04:55:40.915318
7f196a58-d4ea-47a5-b474-11b3be44a933	959e130a-79df-4263-a343-377633591ccd	ziaYVl5tmybTTtKYintWOh132Nu1	2025-11-11 04:56:03.126267
358deaf4-b2ba-402e-8631-16fb16c537d2	9ee703cc-7845-4c50-8036-dc3b79df5672	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 04:59:10.886095
5eea44e7-f9b7-4bc6-b6ed-c1ba4c885dcf	9ee703cc-7845-4c50-8036-dc3b79df5672	ziaYVl5tmybTTtKYintWOh132Nu1	2025-11-11 04:59:33.721067
c273629c-561f-4d79-8a6f-16a7dde1217e	46446a03-721f-4914-b662-2023723acb05	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 05:02:26.570738
d9fd7f78-20ac-4aeb-a51c-0027049c90ec	46446a03-721f-4914-b662-2023723acb05	ziaYVl5tmybTTtKYintWOh132Nu1	2025-11-11 06:22:26.213177
0b4c438d-c044-45bb-9c75-3e516a34c6ce	22b2757a-1bba-41ad-82cd-69ba5126a2a0	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 07:03:57.872078
71a49fc0-8a41-4f9f-929c-89a575c0c8be	fab794ab-d81a-4625-b1e4-42b4ee3f808a	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-11 22:20:31.824426
b981b3b7-8168-42a4-b1f6-6dba260a8a2b	eb3fcda2-17e6-4c71-85c8-55d5a4968c38	AhER0mwPThPo47WaOIvz2IQk19Q2	2025-11-12 07:05:25.466833
\.


--
-- Data for Name: content_submissions; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.content_submissions (uid, job_uid, influencer_uid, media_type, media_url, file_name, file_size, mime_type, duration_sec, resolution, submitted_at, approved_at, rejected_at) FROM stdin;
284adc27-b53d-4f79-94ab-95992b6eeb15	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	ziaYVl5tmybTTtKYintWOh132Nu1	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FziaYVl5tmybTTtKYintWOh132Nu1%2F1762835810701_33.jpg?alt=media&token=566a8d02-99fb-4b58-b132-cff0857fe402	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:36:55.698672	2025-11-11 04:37:51.395896	\N
6aca4749-8b81-4c5a-9f64-8d669ad3ba8d	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	AhER0mwPThPo47WaOIvz2IQk19Q2	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762835781085_33.jpg?alt=media&token=2f10f04c-1b19-406a-acaa-9821dcdf8ee8	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:36:26.300716	2025-11-11 04:38:14.070273	\N
e5d618ab-0f28-4d4a-a804-18075ee09d20	aca16e5d-f074-4410-b89a-6da5a36d9d0e	ziaYVl5tmybTTtKYintWOh132Nu1	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FziaYVl5tmybTTtKYintWOh132Nu1%2F1762836314063_33.jpg?alt=media&token=a02ec39e-d6f8-4ae5-9d39-9ad6b0f7643f	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:45:19.146485	\N	\N
9020a822-ddd3-4e4a-9973-0371bfac995a	aca16e5d-f074-4410-b89a-6da5a36d9d0e	AhER0mwPThPo47WaOIvz2IQk19Q2	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762836749651_33.jpg?alt=media&token=77675c49-af78-4c78-aee1-09474adb13c6	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:52:34.865908	\N	\N
68540d76-2baf-4749-a7e5-9536de1282b6	959e130a-79df-4263-a343-377633591ccd	ziaYVl5tmybTTtKYintWOh132Nu1	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FziaYVl5tmybTTtKYintWOh132Nu1%2F1762836964516_33.jpg?alt=media&token=44b718ac-f4c0-43ef-aa8a-18efc02db828	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:56:09.588064	2025-11-11 04:56:28.293026	\N
a1d7a74e-1043-4ad8-8455-af97ab04ea63	fab794ab-d81a-4625-b1e4-42b4ee3f808a	AhER0mwPThPo47WaOIvz2IQk19Q2	video	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762899635925_35.mp4?alt=media&token=d7d70072-0627-4640-a0e6-c974c95ab089	35.mp4	336278	video/mp4	7431	640x360	2025-11-11 22:20:45.908914	2025-11-12 07:04:16.699032	\N
db59cbbc-f086-4b57-9869-8e3929b86850	9ee703cc-7845-4c50-8036-dc3b79df5672	ziaYVl5tmybTTtKYintWOh132Nu1	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FziaYVl5tmybTTtKYintWOh132Nu1%2F1762837174184_33.jpg?alt=media&token=5536d952-0869-4951-ae33-1a1530613e98	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 04:59:39.27284	2025-11-11 04:59:58.359387	\N
ce9dac72-913a-4146-879e-d76cbc428d61	eb3fcda2-17e6-4c71-85c8-55d5a4968c38	AhER0mwPThPo47WaOIvz2IQk19Q2	video	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762931149359_34.mkv?alt=media&token=7e9ffccc-46cf-402c-a4fd-99728758abab	34.mkv	102737	video/x-matroska	3633	1920x1080	2025-11-12 07:05:53.739513	\N	\N
726623a9-801c-4380-b4d9-543d935a80b8	46446a03-721f-4914-b662-2023723acb05	AhER0mwPThPo47WaOIvz2IQk19Q2	image	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762837348556_33.jpg?alt=media&token=a7e01ab2-1c31-4561-ac88-6033940b270b	33.jpg	2029	image/jpeg	\N	222x180	2025-11-11 05:02:34.310773	2025-11-11 05:03:29.432744	\N
0eb10049-c9ce-4336-956c-cbf35753cd18	46446a03-721f-4914-b662-2023723acb05	ziaYVl5tmybTTtKYintWOh132Nu1	video	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FziaYVl5tmybTTtKYintWOh132Nu1%2F1762842151484_35.mp4?alt=media&token=d63ce255-7d23-4f83-83c5-b40a0eec1afc	35.mp4	336278	video/mp4	7431	640x360	2025-11-11 06:22:43.483968	2025-11-11 06:28:54.4187	\N
1e93a3d9-4688-4af3-b841-1b5f171d555e	22b2757a-1bba-41ad-82cd-69ba5126a2a0	AhER0mwPThPo47WaOIvz2IQk19Q2	video	https://firebasestorage.googleapis.com/v0/b/promoteme-b6c10.firebasestorage.app/o/user_uploads%2FAhER0mwPThPo47WaOIvz2IQk19Q2%2F1762844652245_35.mp4?alt=media&token=eab443cc-efea-4917-95da-2739a6cbcac6	35.mp4	336278	video/mp4	7431	640x360	2025-11-11 07:04:24.910369	2025-11-11 07:05:15.709814	\N
\.


--
-- Data for Name: escrow_events; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.escrow_events (event_uid, escrow_uid, event_type, event_details, created_at) FROM stdin;
1	7b154aa1-e7e5-4dff-9865-15baaaecea9a	Influencer_paid	Job 7b154aa1-e7e5-4dff-9865-15baaaecea9a: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to AhER0mwPThPo47WaOIvz2IQk19Q2 released and closed.	2025-11-11 04:39:18.425516
2	c8be1930-a9f2-40a3-930a-1637143a7a39	Influencer_paid	Job c8be1930-a9f2-40a3-930a-1637143a7a39: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to ziaYVl5tmybTTtKYintWOh132Nu1 released and closed.	2025-11-11 04:39:18.425516
3	d1e1add9-4d73-48f3-8f07-391d0b375b75	Influencer_paid	Job d1e1add9-4d73-48f3-8f07-391d0b375b75: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to ziaYVl5tmybTTtKYintWOh132Nu1 released and closed.	2025-11-11 04:56:48.832542
4	66b8e7ea-a40a-4e29-b107-6bb14d95379e	Influencer_paid	Job 66b8e7ea-a40a-4e29-b107-6bb14d95379e: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to ziaYVl5tmybTTtKYintWOh132Nu1 released and closed.	2025-11-11 05:00:08.940109
5	bbc39b21-6ad1-4ce9-9a8c-8614db4cd578	Influencer_paid	Job bbc39b21-6ad1-4ce9-9a8c-8614db4cd578: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to AhER0mwPThPo47WaOIvz2IQk19Q2 released and closed.	2025-11-11 07:05:45.024549
6	9e7cd174-255e-4783-9431-7d2330136137	Influencer_paid	Job 9e7cd174-255e-4783-9431-7d2330136137: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to AhER0mwPThPo47WaOIvz2IQk19Q2 released and closed.	2025-11-11 07:05:45.024549
7	3df5a0eb-6af8-4e84-96f6-60bb7cb05715	Influencer_paid	Job 3df5a0eb-6af8-4e84-96f6-60bb7cb05715: payment from HzndfCPj0aMzS89wIad1HObPOyq1 to ziaYVl5tmybTTtKYintWOh132Nu1 released and closed.	2025-11-11 07:05:46.895701
\.


--
-- Data for Name: escrow_transactions; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.escrow_transactions (escrow_uid, buyer_uid, seller_uid, payment_amount, payment_time, escrow_released_time, status) FROM stdin;
7b154aa1-e7e5-4dff-9865-15baaaecea9a	HzndfCPj0aMzS89wIad1HObPOyq1	AhER0mwPThPo47WaOIvz2IQk19Q2	20.00	2025-11-11 04:38:14.070273	2025-11-11 04:39:18.425516	released
c8be1930-a9f2-40a3-930a-1637143a7a39	HzndfCPj0aMzS89wIad1HObPOyq1	ziaYVl5tmybTTtKYintWOh132Nu1	20.00	2025-11-11 04:37:51.395896	2025-11-11 04:39:18.425516	released
d1e1add9-4d73-48f3-8f07-391d0b375b75	HzndfCPj0aMzS89wIad1HObPOyq1	ziaYVl5tmybTTtKYintWOh132Nu1	20.00	2025-11-11 04:56:28.293026	2025-11-11 04:56:48.832542	released
66b8e7ea-a40a-4e29-b107-6bb14d95379e	HzndfCPj0aMzS89wIad1HObPOyq1	ziaYVl5tmybTTtKYintWOh132Nu1	20.00	2025-11-11 04:59:58.359387	2025-11-11 05:00:08.940109	released
bbc39b21-6ad1-4ce9-9a8c-8614db4cd578	HzndfCPj0aMzS89wIad1HObPOyq1	AhER0mwPThPo47WaOIvz2IQk19Q2	20.00	2025-11-11 05:03:29.432744	2025-11-11 07:05:45.024549	released
9e7cd174-255e-4783-9431-7d2330136137	HzndfCPj0aMzS89wIad1HObPOyq1	AhER0mwPThPo47WaOIvz2IQk19Q2	20.00	2025-11-11 07:05:15.709814	2025-11-11 07:05:45.024549	released
3df5a0eb-6af8-4e84-96f6-60bb7cb05715	HzndfCPj0aMzS89wIad1HObPOyq1	ziaYVl5tmybTTtKYintWOh132Nu1	20.00	2025-11-11 06:28:54.4187	2025-11-11 07:05:46.895701	released
1f7bb698-1fd9-4f48-a530-888de616e285	HzndfCPj0aMzS89wIad1HObPOyq1	AhER0mwPThPo47WaOIvz2IQk19Q2	20.00	2025-11-12 07:04:16.699032	\N	pending
\.


--
-- Data for Name: financial_analytics; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.financial_analytics (date, total_payouts, payouts_count, total_refunds, refunds_count, total_paid_for_campaigns, net_revenue, largest_single_payout, largest_single_refund) FROM stdin;
2025-11-09	20.00	1	150.00	3	170.00	0.00	20.00	75.00
2025-11-11	140.00	7	450.00	6	590.00	0.00	20.00	100.00
2025-11-12	140.00	7	450.00	6	590.00	0.00	20.00	100.00
\.


--
-- Data for Name: influencer_jobs; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.influencer_jobs (uid, user_uid, job_uid, assigned_at, closed_at, amount, content_done_at, content_approved_at) FROM stdin;
3092a732-ad9c-48f1-b56b-b5351c91a2b1	AhER0mwPThPo47WaOIvz2IQk19Q2	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	2025-11-11 04:35:56.685195	2025-11-11 04:39:18.425516	20	2025-11-11 04:36:26.307637	2025-11-11 04:38:14.070273
2ada3ae0-865e-409d-a7b8-4ab9ee4dbaa5	ziaYVl5tmybTTtKYintWOh132Nu1	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	2025-11-11 04:36:50.018399	2025-11-11 04:39:18.425516	20	2025-11-11 04:36:55.701945	2025-11-11 04:37:51.395896
633c0881-48e9-4d8d-8633-5e8097d67cde	AhER0mwPThPo47WaOIvz2IQk19Q2	aca16e5d-f074-4410-b89a-6da5a36d9d0e	2025-11-11 04:39:52.980614	2025-11-11 04:55:12.146007	20	2025-11-11 04:52:34.891346	\N
c9cbbac3-3b42-4d5f-bd04-aa5e68056348	ziaYVl5tmybTTtKYintWOh132Nu1	aca16e5d-f074-4410-b89a-6da5a36d9d0e	2025-11-11 04:43:59.636764	2025-11-11 04:55:12.146007	20	2025-11-11 04:45:19.18078	\N
82b8fd3c-9175-412d-b01d-8ca0e9449aa1	ziaYVl5tmybTTtKYintWOh132Nu1	959e130a-79df-4263-a343-377633591ccd	2025-11-11 04:56:03.126267	2025-11-11 04:56:48.832542	20	2025-11-11 04:56:09.592339	2025-11-11 04:56:28.293026
1ca1450c-7a3a-40b5-bbf6-5ff774e24929	ziaYVl5tmybTTtKYintWOh132Nu1	9ee703cc-7845-4c50-8036-dc3b79df5672	2025-11-11 04:59:33.721067	2025-11-11 05:00:08.940109	20	2025-11-11 04:59:39.277905	2025-11-11 04:59:58.359387
5395e86d-f0eb-4721-81f3-0bec0e9cfb67	AhER0mwPThPo47WaOIvz2IQk19Q2	22b2757a-1bba-41ad-82cd-69ba5126a2a0	2025-11-11 07:03:57.872078	2025-11-11 07:05:45.024549	20	2025-11-11 07:04:24.91554	2025-11-11 07:05:15.709814
4fc83858-4368-42ad-85ca-a62b7a8a3954	AhER0mwPThPo47WaOIvz2IQk19Q2	46446a03-721f-4914-b662-2023723acb05	2025-11-11 05:02:26.570738	2025-11-11 07:05:46.895701	20	2025-11-11 05:02:34.316697	2025-11-11 05:03:29.432744
4b12129e-4ccd-4d09-83ce-bb9ad0be9994	ziaYVl5tmybTTtKYintWOh132Nu1	46446a03-721f-4914-b662-2023723acb05	2025-11-11 06:22:26.213177	2025-11-11 07:05:46.895701	20	2025-11-11 06:22:43.491868	2025-11-11 06:28:54.4187
a6dee8c8-4ba8-46a6-aabc-19572538e00a	AhER0mwPThPo47WaOIvz2IQk19Q2	fab794ab-d81a-4625-b1e4-42b4ee3f808a	2025-11-11 22:20:31.824426	\N	20	2025-11-11 22:20:45.915566	2025-11-12 07:04:16.699032
d241df54-636f-499d-b27e-65c78f9a78a6	AhER0mwPThPo47WaOIvz2IQk19Q2	eb3fcda2-17e6-4c71-85c8-55d5a4968c38	2025-11-12 07:05:25.466833	\N	20	2025-11-12 07:05:53.743524	\N
\.


--
-- Data for Name: influencer_logs; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.influencer_logs (uid, user_uid, job_uid, description, log, created_at) FROM stdin;
5c6256ae-b2e6-424a-abd2-f1c740717057	AhER0mwPThPo47WaOIvz2IQk19Q2	aca16e5d-f074-4410-b89a-6da5a36d9d0e	Client CLOSED WITHOUT APPROVING submitted content	{"amount": 20, "closed_at": "2025-11-11T04:55:12.146007", "content_done_at": "2025-11-11T04:52:34.891346", "content_approved_at": null}	2025-11-11 04:55:12.146007+00
6a92b8d4-4071-423c-aca9-c58db665aa83	ziaYVl5tmybTTtKYintWOh132Nu1	aca16e5d-f074-4410-b89a-6da5a36d9d0e	Client CLOSED WITHOUT APPROVING submitted content	{"amount": 20, "closed_at": "2025-11-11T04:55:12.146007", "content_done_at": "2025-11-11T04:45:19.18078", "content_approved_at": null}	2025-11-11 04:55:12.146007+00
8c05c5e6-40cc-4b34-b17d-ed0103250d8e	AhER0mwPThPo47WaOIvz2IQk19Q2	959e130a-79df-4263-a343-377633591ccd	Influencer removed from job	{"event": "influencer_job_deleted", "reason": "Artist removed influencer from campaign", "job_uid": "959e130a-79df-4263-a343-377633591ccd", "timestamp": "2025-11-11T04:56:35.72796+00:00", "deleted_record": {"amount": 20, "closed_at": null, "assigned_at": "2025-11-11T04:55:40.915318", "content_done_at": null, "content_approved_at": null, "influencer_jobs_uid": "742f420b-13e8-4289-b2ba-a3edef4d2bad"}, "influencer_uid": "AhER0mwPThPo47WaOIvz2IQk19Q2", "database_action": "DELETE"}	2025-11-11 04:56:35.72796+00
a3b11e7f-dadf-486f-b839-1bf1ec874058	AhER0mwPThPo47WaOIvz2IQk19Q2	9ee703cc-7845-4c50-8036-dc3b79df5672	Influencer removed from job	{"event": "influencer_job_deleted", "reason": "Artist removed influencer from campaign", "job_uid": "9ee703cc-7845-4c50-8036-dc3b79df5672", "timestamp": "2025-11-11T05:00:05.06998+00:00", "deleted_record": {"amount": 20, "closed_at": null, "assigned_at": "2025-11-11T04:59:10.886095", "content_done_at": null, "content_approved_at": null, "influencer_jobs_uid": "a06b5672-fb11-40b8-8c9f-640aa11f021e"}, "influencer_uid": "AhER0mwPThPo47WaOIvz2IQk19Q2", "database_action": "DELETE"}	2025-11-11 05:00:05.06998+00
\.


--
-- Data for Name: influencer_payouts; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.influencer_payouts (uid, user_uid, job_uid, amount, genre, issued_at, payed_at) FROM stdin;
261f05da-1492-48b6-96b7-26176cb0026a	AhER0mwPThPo47WaOIvz2IQk19Q2	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	20	Dubstep	2025-11-11 04:39:18.425516	2025-11-11 04:39:18.425516
6623495a-c866-49bc-9fdd-5b2eb6de477f	ziaYVl5tmybTTtKYintWOh132Nu1	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	20	Dubstep	2025-11-11 04:39:18.425516	2025-11-11 04:39:18.425516
9d432460-3794-44a7-86a3-9d6fd3029f9a	ziaYVl5tmybTTtKYintWOh132Nu1	959e130a-79df-4263-a343-377633591ccd	20	Dubstep	2025-11-11 04:56:48.832542	2025-11-11 04:56:48.832542
8c913b7f-083f-4a1e-a0e7-7e251c8a3d37	ziaYVl5tmybTTtKYintWOh132Nu1	9ee703cc-7845-4c50-8036-dc3b79df5672	20	Dubstep	2025-11-11 05:00:08.940109	2025-11-11 05:00:08.940109
05debaba-7ba2-45cf-91ef-1206e4d13a50	AhER0mwPThPo47WaOIvz2IQk19Q2	22b2757a-1bba-41ad-82cd-69ba5126a2a0	20	Dubstep	2025-11-11 07:05:45.024549	2025-11-11 07:05:45.024549
4c01f83d-c7d7-4c29-bee6-5c2913268e29	AhER0mwPThPo47WaOIvz2IQk19Q2	46446a03-721f-4914-b662-2023723acb05	20	Dubstep	2025-11-11 07:05:46.895701	2025-11-11 07:05:46.895701
24fd90c8-9724-4d47-82ff-cc78666435b6	ziaYVl5tmybTTtKYintWOh132Nu1	46446a03-721f-4914-b662-2023723acb05	20	Dubstep	2025-11-11 07:05:46.895701	2025-11-11 07:05:46.895701
\.


--
-- Data for Name: joblogs; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.joblogs (uid, job_uid, description, log, created_at) FROM stdin;
0dda8518-f56b-4cdc-8453-ec78e5b6de98	a8f20411-fbc6-4999-b32b-0916bdf7ccf9	Job closed within a day of creation	{"genre": "Dubstep", "end_date": "2025-11-13", "closed_at": "2025-11-11T04:39:18.425516", "max_slots": 2, "created_at": "2025-11-11T04:35:40.443009", "claim_count": 2, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 2, "all_content_ready": "2025-11-11T04:36:55.701945"}	2025-11-11 04:39:18.425516+00
3922d689-1bf1-4afd-b752-50acafd7dc0d	57e1c593-107e-47c5-a5fb-259b55170849	Job closed within a day of creation; Job closed before all content was ready	{"genre": "Dubstep", "end_date": "2025-11-19", "closed_at": "2025-11-11T04:54:09.092699", "max_slots": 4, "created_at": "2025-11-11T04:54:00.929425", "claim_count": 0, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 0, "all_content_ready": null}	2025-11-11 04:54:09.092699+00
0d1b1c66-21c3-43ac-befe-289d5013cf84	aca16e5d-f074-4410-b89a-6da5a36d9d0e	Job closed within a day of creation	{"genre": "Dubstep", "end_date": "2025-11-18", "closed_at": "2025-11-11T04:55:12.146007", "max_slots": 4, "created_at": "2025-11-11T04:39:33.306456", "claim_count": 2, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 2, "all_content_ready": "2025-11-11T04:52:34.891346"}	2025-11-11 04:55:12.146007+00
5e713f9e-5dc6-466a-bcc8-e07590b7dff3	959e130a-79df-4263-a343-377633591ccd	Closed on influencers who submitted work without approving the work; Job closed within a day of creation; Job closed before all content was ready	{"genre": "Dubstep", "end_date": "2025-11-19", "closed_at": "2025-11-11T04:56:48.832542", "max_slots": 4, "created_at": "2025-11-11T04:55:25.166228", "claim_count": 1, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 1, "all_content_ready": null}	2025-11-11 04:56:48.832542+00
9ed2437e-f038-4f9b-b9f2-c78f7a5b611a	9ee703cc-7845-4c50-8036-dc3b79df5672	Closed on influencers who submitted work without approving the work; Job closed within a day of creation; Job closed before all content was ready	{"genre": "Dubstep", "end_date": "2025-11-21", "closed_at": "2025-11-11T05:00:08.940109", "max_slots": 4, "created_at": "2025-11-11T04:58:55.058026", "claim_count": 1, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 1, "all_content_ready": null}	2025-11-11 05:00:08.940109+00
e9b69668-f1e7-491b-b0b6-ef08d4332107	22b2757a-1bba-41ad-82cd-69ba5126a2a0	Job closed within a day of creation	{"genre": "Dubstep", "end_date": "2025-11-21", "closed_at": "2025-11-11T07:05:45.024549", "max_slots": 3, "created_at": "2025-11-11T07:03:25.07688", "claim_count": 1, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 1, "all_content_ready": "2025-11-11T07:04:24.91554"}	2025-11-11 07:05:45.024549+00
cd84b4e4-f323-4040-893b-f2342b937557	46446a03-721f-4914-b662-2023723acb05	Job closed within a day of creation	{"genre": "Dubstep", "end_date": "2025-11-26", "closed_at": "2025-11-11T07:05:46.895701", "max_slots": 4, "created_at": "2025-11-11T05:02:09.880137", "claim_count": 2, "creator_uid": "HzndfCPj0aMzS89wIad1HObPOyq1", "influencers_done": 2, "all_content_ready": "2025-11-11T06:22:43.491868"}	2025-11-11 07:05:46.895701+00
\.


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.jobs (uid, title, description, budget, influencer_slots, influence_min, influence_max, location, genre, creator_uid, status, created_at, closed_at, max_slots, influencers_done, all_content_ready, end_date, stripe_charge_id, all_approved_at, approved) FROM stdin;
9ee703cc-7845-4c50-8036-dc3b79df5672	test	test	100	3	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 04:58:55.058026	2025-11-11 05:00:08.940109	4	1	\N	2025-11-21	pi_3SS9fOB9mbMy83Mm0LcPu2an	2025-11-11 04:59:59.558448	1
a8f20411-fbc6-4999-b32b-0916bdf7ccf9	test	test	50	0	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 04:35:40.443009	2025-11-11 04:39:18.425516	2	2	2025-11-11 04:36:55.701945	2025-11-13	pi_3SS9IuB9mbMy83Mm0QftZ3Cf	2025-11-11 04:38:14.074012	2
57e1c593-107e-47c5-a5fb-259b55170849	testt	testt	100	4	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 04:54:00.929425	2025-11-11 04:54:09.092699	4	0	\N	2025-11-19	pi_3SS9aeB9mbMy83Mm0FO0ayzR	\N	0
aca16e5d-f074-4410-b89a-6da5a36d9d0e	test	tes	100	2	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 04:39:33.306456	2025-11-11 04:55:12.146007	4	2	2025-11-11 04:52:34.891346	2025-11-18	pi_3SS9MfB9mbMy83Mm1VKIfmr7	\N	0
959e130a-79df-4263-a343-377633591ccd	test	test	100	3	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 04:55:25.166228	2025-11-11 04:56:48.832542	4	1	\N	2025-11-19	pi_3SS9c1B9mbMy83Mm08t63JFg	2025-11-11 04:56:29.793162	1
22b2757a-1bba-41ad-82cd-69ba5126a2a0	tes	test	75	2	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 07:03:25.07688	2025-11-11 07:05:45.024549	3	1	2025-11-11 07:04:24.91554	2025-11-21	pi_3SSBbtB9mbMy83Mm0x4b5M9k	2025-11-11 07:05:15.715941	1
46446a03-721f-4914-b662-2023723acb05	test	test	100	2	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	closed	2025-11-11 05:02:09.880137	2025-11-11 07:05:46.895701	4	2	2025-11-11 06:22:43.491868	2025-11-26	pi_3SS9iXB9mbMy83Mm1PSdBIWE	2025-11-11 06:28:54.845404	2
fab794ab-d81a-4625-b1e4-42b4ee3f808a	test	test	75	2	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	open	2025-11-11 22:20:01.901014	\N	3	1	2025-11-11 22:20:45.915566	2025-11-19	pi_3SSPuuB9mbMy83Mm1o8ZCnTo	2025-11-12 07:04:16.730289	1
eb3fcda2-17e6-4c71-85c8-55d5a4968c38	test	test	75	2	1	9999	LA	Dubstep	HzndfCPj0aMzS89wIad1HObPOyq1	open	2025-11-12 07:04:07.52515	\N	3	1	2025-11-12 07:05:53.743524	2025-11-27	pi_3SSY67B9mbMy83Mm0U7pDDxe	\N	0
\.


--
-- Data for Name: platform_analytics; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.platform_analytics (date, total_users, total_artists, total_influencers, active_users_daily, jobs_created, jobs_closed, influencers_paid, full_job_rate, current_open_jobs) FROM stdin;
2025-11-09	3	1	2	3	4	3	1	0.3333	1
2025-11-11	3	1	2	3	7	7	7	0.1429	0
2025-11-12	3	1	2	2	9	7	7	0.1429	2
\.


--
-- Data for Name: system_logs; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.system_logs (uid, source_uid, log_time, data) FROM stdin;
\.


--
-- Data for Name: unfilled_refunds; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.unfilled_refunds (uid, user_uid, job_uid, max_slots, approved_slots, budget, refunded, issued_at, created_at, stripe_refund_id, stripe_charge_id) FROM stdin;
068184ff-80c6-48a7-905b-8b76a1a64495	HzndfCPj0aMzS89wIad1HObPOyq1	57e1c593-107e-47c5-a5fb-259b55170849	4	0	100.00	100.00	2025-11-11 08:05:01.068577	2025-11-11 04:54:09.092699	re_3SS9aeB9mbMy83Mm0yLcBlIO	pi_3SS9aeB9mbMy83Mm0FO0ayzR
3fdfcefd-d889-48c0-8d84-5ac293c66c75	HzndfCPj0aMzS89wIad1HObPOyq1	aca16e5d-f074-4410-b89a-6da5a36d9d0e	4	0	100.00	100.00	2025-11-11 08:05:01.911074	2025-11-11 04:55:12.146007	re_3SS9MfB9mbMy83Mm1OUUHZKf	pi_3SS9MfB9mbMy83Mm1VKIfmr7
d3d0604a-18fd-4365-bac9-79857bbc72c2	HzndfCPj0aMzS89wIad1HObPOyq1	959e130a-79df-4263-a343-377633591ccd	4	1	100.00	75.00	2025-11-11 08:05:02.696528	2025-11-11 04:56:48.832542	re_3SS9c1B9mbMy83Mm0gTLqKOx	pi_3SS9c1B9mbMy83Mm08t63JFg
41b6fe25-d2bc-48fd-9e20-ed9399d93028	HzndfCPj0aMzS89wIad1HObPOyq1	9ee703cc-7845-4c50-8036-dc3b79df5672	4	1	100.00	75.00	2025-11-11 08:05:03.612145	2025-11-11 05:00:08.940109	re_3SS9fOB9mbMy83Mm0yoVc7Q7	pi_3SS9fOB9mbMy83Mm0LcPu2an
05ac2c62-15f5-45ad-99f8-71867b39254e	HzndfCPj0aMzS89wIad1HObPOyq1	22b2757a-1bba-41ad-82cd-69ba5126a2a0	3	1	75.00	50.00	2025-11-11 08:05:04.565115	2025-11-11 07:05:45.024549	re_3SSBbtB9mbMy83Mm0LPr58XL	pi_3SSBbtB9mbMy83Mm0x4b5M9k
f1216cb1-46b8-4892-8b5b-9bbfc4509e98	HzndfCPj0aMzS89wIad1HObPOyq1	46446a03-721f-4914-b662-2023723acb05	4	2	100.00	50.00	2025-11-11 08:05:05.516756	2025-11-11 07:05:46.895701	re_3SS9iXB9mbMy83Mm1cuvukbD	pi_3SS9iXB9mbMy83Mm1PSdBIWE
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: nullandvoid
--

COPY public.users (uid, email, password, display_name, phone_number, bio, created_at, socials, payment_methods, user_type, wallet, last_active, location, is_valid) FROM stdin;
ziaYVl5tmybTTtKYintWOh132Nu1	i2@mail.com	\N	i2	\N	Dubstep	2025-11-11 01:57:13.04171	{}	{"stripe": {"customerId": "cus_TOueY4u6qWZiHV", "paymentMethodId": "pm_1SS6pYB9mbMy83MmfelurZBr", "connectAccountId": "acct_1SSBouPW9VZ2R7Ou"}}	influencer	100.00	2025-11-11 07:16:54.882343	LA	t
AhER0mwPThPo47WaOIvz2IQk19Q2	i@mail.com	\N	i	\N	Dubstep	2025-11-10 06:13:02.340019	{}	{"stripe": {"customerId": "cus_TObYvs0wnkyniB", "paymentMethodId": "pm_1SRoLaB9mbMy83MmOu5e7IIE", "connectAccountId": "acct_1SSQWCBSfcxOHUxl"}}	influencer	0.00	2025-11-12 07:12:25.964053	LA	t
HzndfCPj0aMzS89wIad1HObPOyq1	a@mail.com	\N	a	\N	ARTIST	2025-11-10 06:11:57.879669	{}	{"stripe": {"customerId": "cus_TObXUrsyN5ituN", "paymentMethodId": "pm_1SRoKXB9mbMy83MmabedYldg"}}	artist	20.00	2025-11-12 07:09:41.096985		t
\.


--
-- Name: escrow_events_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: nullandvoid
--

SELECT pg_catalog.setval('public.escrow_events_event_id_seq', 7, true);


--
-- Name: claims claims_job_id_influencer_id_key; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_job_id_influencer_id_key UNIQUE (job_id, influencer_id);


--
-- Name: claims claims_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_pkey PRIMARY KEY (id);


--
-- Name: content_submissions content_submissions_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.content_submissions
    ADD CONSTRAINT content_submissions_pkey PRIMARY KEY (uid);


--
-- Name: escrow_events escrow_events_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.escrow_events
    ADD CONSTRAINT escrow_events_pkey PRIMARY KEY (event_uid);


--
-- Name: escrow_transactions escrow_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.escrow_transactions
    ADD CONSTRAINT escrow_transactions_pkey PRIMARY KEY (escrow_uid);


--
-- Name: financial_analytics financial_analytics_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.financial_analytics
    ADD CONSTRAINT financial_analytics_pkey PRIMARY KEY (date);


--
-- Name: influencer_logs influencer_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_logs
    ADD CONSTRAINT influencer_logs_pkey PRIMARY KEY (uid);


--
-- Name: influencer_payouts influencer_payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_payouts
    ADD CONSTRAINT influencer_payouts_pkey PRIMARY KEY (uid);


--
-- Name: joblogs joblogs_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.joblogs
    ADD CONSTRAINT joblogs_pkey PRIMARY KEY (uid);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (uid);


--
-- Name: platform_analytics platform_analytics_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.platform_analytics
    ADD CONSTRAINT platform_analytics_pkey PRIMARY KEY (date);


--
-- Name: system_logs system_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.system_logs
    ADD CONSTRAINT system_logs_pkey PRIMARY KEY (uid);


--
-- Name: unfilled_refunds unfilled_refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.unfilled_refunds
    ADD CONSTRAINT unfilled_refunds_pkey PRIMARY KEY (uid);


--
-- Name: influencer_jobs user_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_jobs
    ADD CONSTRAINT user_jobs_pkey PRIMARY KEY (uid);


--
-- Name: influencer_jobs user_jobs_user_uid_job_uid_key; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_jobs
    ADD CONSTRAINT user_jobs_user_uid_job_uid_key UNIQUE (user_uid, job_uid);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (uid);


--
-- Name: idx_jobs_genre_location; Type: INDEX; Schema: public; Owner: nullandvoid
--

CREATE INDEX idx_jobs_genre_location ON public.jobs USING btree (genre, location) WHERE (influencer_slots > 0);


--
-- Name: escrow_transactions escrow_released_trigger; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER escrow_released_trigger AFTER UPDATE ON public.escrow_transactions FOR EACH ROW WHEN ((old.escrow_released_time IS DISTINCT FROM new.escrow_released_time)) EXECUTE FUNCTION public.log_escrow_released();


--
-- Name: financial_analytics financial_analytics_before_insert; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER financial_analytics_before_insert BEFORE INSERT ON public.financial_analytics FOR EACH ROW EXECUTE FUNCTION public.populate_financial_analytics();


--
-- Name: influencer_jobs influencer_job_deletion_log; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER influencer_job_deletion_log AFTER DELETE ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.log_influencer_job_deletion();


--
-- Name: jobs jobs_closed_at_logging; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER jobs_closed_at_logging AFTER UPDATE OF closed_at ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.log_job_issues();


--
-- Name: jobs jobs_set_max_slots; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER jobs_set_max_slots BEFORE INSERT ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.set_max_slots();


--
-- Name: jobs trg_check_influencers_done; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_check_influencers_done BEFORE UPDATE OF influencers_done ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.log_influencers_done_limit('influencers_done');


--
-- Name: jobs trg_close_influencer_jobs; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_close_influencer_jobs AFTER UPDATE OF closed_at ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.close_related_influencer_jobs();


--
-- Name: content_submissions trg_content_approve_update; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_content_approve_update AFTER UPDATE OF approved_at ON public.content_submissions FOR EACH ROW EXECUTE FUNCTION public.trg_update_influencer_job_on_approve();


--
-- Name: content_submissions trg_content_reject_reset; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_content_reject_reset AFTER UPDATE OF rejected_at ON public.content_submissions FOR EACH ROW EXECUTE FUNCTION public.trg_reset_influencer_job_on_reject();


--
-- Name: influencer_jobs trg_create_claim_on_influencer_job; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_create_claim_on_influencer_job AFTER INSERT ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.create_claim_on_influencer_job();


--
-- Name: influencer_jobs trg_create_escrow_on_content_approved; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_create_escrow_on_content_approved AFTER UPDATE ON public.influencer_jobs FOR EACH ROW WHEN ((new.content_approved_at IS DISTINCT FROM old.content_approved_at)) EXECUTE FUNCTION public.create_escrow_on_content_approved();


--
-- Name: jobs trg_create_unfilled_refund_trigger; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_create_unfilled_refund_trigger AFTER UPDATE OF closed_at ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.trg_create_unfilled_refund();


--
-- Name: influencer_jobs trg_decrement_influencers_done; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_decrement_influencers_done AFTER UPDATE OF content_done_at ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.trg_decrement_influencers_done();


--
-- Name: influencer_jobs trg_delete_related_content_submissions; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_delete_related_content_submissions AFTER DELETE ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.delete_related_content_submissions();


--
-- Name: influencer_jobs trg_increment_influencers_done; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_increment_influencers_done AFTER UPDATE OF content_done_at ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.increment_influencers_done();


--
-- Name: influencer_jobs trg_influencer_jobs_closed; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_influencer_jobs_closed BEFORE UPDATE ON public.influencer_jobs FOR EACH ROW WHEN ((old.closed_at IS DISTINCT FROM new.closed_at)) EXECUTE FUNCTION public.set_amount_zero_if_closed_without_content();


--
-- Name: influencer_jobs trg_influencer_payout; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_influencer_payout AFTER UPDATE ON public.influencer_jobs FOR EACH ROW WHEN ((old.closed_at IS DISTINCT FROM new.closed_at)) EXECUTE FUNCTION public.create_influencer_payout();


--
-- Name: influencer_jobs trg_log_unapproved_closure; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_log_unapproved_closure AFTER UPDATE OF closed_at ON public.influencer_jobs FOR EACH ROW WHEN ((old.closed_at IS DISTINCT FROM new.closed_at)) EXECUTE FUNCTION public.log_unapproved_closure();


--
-- Name: platform_analytics trg_platform_analytics; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_platform_analytics BEFORE INSERT ON public.platform_analytics FOR EACH ROW EXECUTE FUNCTION public.populate_platform_analytics();


--
-- Name: unfilled_refunds trg_prevent_invalid_refund; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_invalid_refund BEFORE INSERT OR UPDATE ON public.unfilled_refunds FOR EACH ROW EXECUTE FUNCTION public.prevent_invalid_refund();


--
-- Name: influencer_jobs trg_prevent_updates_after_closed; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_updates_after_closed BEFORE UPDATE ON public.influencer_jobs FOR EACH ROW WHEN ((old.closed_at IS NOT NULL)) EXECUTE FUNCTION public.prevent_modifications_after_closed();


--
-- Name: jobs trg_prevent_updates_after_closed; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_updates_after_closed BEFORE UPDATE ON public.jobs FOR EACH ROW WHEN ((old.closed_at IS NOT NULL)) EXECUTE FUNCTION public.prevent_modifications_after_closed();


--
-- Name: unfilled_refunds trg_prevent_updates_after_closed; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_updates_after_closed BEFORE UPDATE ON public.unfilled_refunds FOR EACH ROW WHEN ((old.issued_at IS NOT NULL)) EXECUTE FUNCTION public.prevent_modifications_after_closed();


--
-- Name: unfilled_refunds trg_prevent_updates_after_refund_issued; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_updates_after_refund_issued BEFORE UPDATE ON public.unfilled_refunds FOR EACH ROW WHEN ((old.issued_at IS NOT NULL)) EXECUTE FUNCTION public.prevent_modifications_after_refund_issued();


--
-- Name: escrow_transactions trg_prevent_updates_after_released; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_prevent_updates_after_released BEFORE UPDATE ON public.escrow_transactions FOR EACH ROW WHEN ((old.escrow_released_time IS NOT NULL)) EXECUTE FUNCTION public.prevent_modifications_after_released();


--
-- Name: influencer_jobs trg_release_escrow_on_close; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_release_escrow_on_close AFTER UPDATE OF closed_at ON public.influencer_jobs FOR EACH ROW EXECUTE FUNCTION public.release_escrow_on_influencer_close();


--
-- Name: jobs trg_reset_all_approved_at_trigger; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_reset_all_approved_at_trigger BEFORE UPDATE ON public.jobs FOR EACH ROW WHEN ((old.all_approved_at IS NOT NULL)) EXECUTE FUNCTION public.trg_reset_all_approved_at();


--
-- Name: jobs trg_reset_all_content_ready; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_reset_all_content_ready AFTER UPDATE OF influencers_done, claim_count ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.reset_all_content_ready();


--
-- Name: jobs trg_set_all_approved_at; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_set_all_approved_at BEFORE UPDATE OF approved, influencers_done ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.trg_update_all_approved_at();


--
-- Name: jobs trg_set_all_content_ready; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_set_all_content_ready AFTER UPDATE OF influencers_done ON public.jobs FOR EACH ROW WHEN ((new.influencers_done = new.claim_count)) EXECUTE FUNCTION public.update_all_content_ready();


--
-- Name: influencer_payouts trg_update_wallet_on_payout; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trg_update_wallet_on_payout AFTER INSERT ON public.influencer_payouts FOR EACH ROW EXECUTE FUNCTION public.update_influencer_wallet();


--
-- Name: users trigger_prevent_negative_wallet; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER trigger_prevent_negative_wallet BEFORE UPDATE OF wallet ON public.users FOR EACH ROW EXECUTE FUNCTION public.prevent_negative_wallet();


--
-- Name: jobs update_status_on_close; Type: TRIGGER; Schema: public; Owner: nullandvoid
--

CREATE TRIGGER update_status_on_close BEFORE UPDATE OF closed_at ON public.jobs FOR EACH ROW EXECUTE FUNCTION public.set_job_status_closed();


--
-- Name: claims claims_influencer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_influencer_id_fkey FOREIGN KEY (influencer_id) REFERENCES public.users(uid);


--
-- Name: claims claims_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.claims
    ADD CONSTRAINT claims_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.jobs(uid) ON DELETE CASCADE;


--
-- Name: content_submissions content_submissions_job_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.content_submissions
    ADD CONSTRAINT content_submissions_job_uid_fkey FOREIGN KEY (job_uid) REFERENCES public.jobs(uid);


--
-- Name: escrow_events escrow_events_escrow_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.escrow_events
    ADD CONSTRAINT escrow_events_escrow_id_fkey FOREIGN KEY (escrow_uid) REFERENCES public.escrow_transactions(escrow_uid);


--
-- Name: jobs jobs_creator_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_creator_id_fkey FOREIGN KEY (creator_uid) REFERENCES public.users(uid);


--
-- Name: influencer_jobs user_jobs_job_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_jobs
    ADD CONSTRAINT user_jobs_job_uid_fkey FOREIGN KEY (job_uid) REFERENCES public.jobs(uid);


--
-- Name: influencer_jobs user_jobs_user_uid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: nullandvoid
--

ALTER TABLE ONLY public.influencer_jobs
    ADD CONSTRAINT user_jobs_user_uid_fkey FOREIGN KEY (user_uid) REFERENCES public.users(uid);


--
-- PostgreSQL database dump complete
--

\unrestrict kZCmpCWcMyoLzI74dib81j8E2PSUswXzCM8dZkupagkftnRuAw4viSHVgXcZ1dE

