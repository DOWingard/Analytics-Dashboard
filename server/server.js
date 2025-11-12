import cors from "cors";
import dotenv from "dotenv";
import express from "express";
import pkg from "pg";
import Stripe from "stripe";
import { v4 as uuidv4 } from "uuid";




// -----------------------------
// --- CONFIGURATION ---
// -----------------------------

const REFUND_WORKER_TIMEFRAME_MS = 24 * 60 * 60 * 1000; // 24 hrs
const JOB_CLOSER_TIMEFRAME_MS =  24 * 60 * 60 * 1000;  // 
const ANALYTICS_WORKER_TIMEFRAME_MS = 24 * 60 * 60 * 1000; // 

const CONNECTED_ACCOUNT_SOURCE = "tok_visa";


// CUT RATE THAT WE TAKE
const __cutRate = 0.2;

// CONTROL LOGGING
const __wantLogs = true;

// Logging helpers
const log = (...args) => {
  if (__wantLogs) console.log(...args);
};

const logError = (...args) => {
  if (__wantLogs) console.error(...args);
};

const logWarn = (...args) => {
  if (__wantLogs) console.warn(...args);
};

dotenv.config();
const { Client } = pkg;

const app = express();

// Middleware
app.use(cors());
app.use(express.json());

// PostgreSQL client
const client = new Client({
  host: process.env.POSTGRES_HOST || "localhost",
  port: Number(process.env.POSTGRES_PORT) || 5432,
  user: process.env.POSTGRES_USER || "nullandvoid",
  password: process.env.POSTGRES_PASSWORD || "Timecube420",
  database: process.env.POSTGRES_DB || "void",
});

// Stripe
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY, {
  apiVersion: "2023-08-16",
});

// Helper function to update last_active (silently handles errors)
const updateLastActive = async (uid) => {
  if (!uid) return;
  try {
    await client.query("UPDATE users SET last_active = NOW() WHERE uid = $1", [uid]);
  } catch (err) {
    logError(`[last_active] Failed to update for ${uid}:`, err.message);
  }
};

// Extract uid from request and update last_active
const extractAndUpdateUser = async (req) => {
  let uid = req.params?.uid || req.body?.uid || req.query?.uid;
  if (uid) await updateLastActive(uid);
  return uid;
};

// -----------------------------
// --- USER ENDPOINTS ---
// -----------------------------

app.post("/create-user", async (req, res) => {
  const {
    uid,
    email,
    password,
    display_name,
    bio = "",
    location = "",
    socials = {},
    payment_methods = {},
    user_type = null,
    wallet = 0,
  } = req.body;

  if (!uid || !email) return res.status(400).json({ error: "UID and email required" });

  try {
    log(`[create-user] Creating user: ${uid} (${email})${location ? ` in ${location}` : ''}`);
    const existing = await client.query("SELECT * FROM users WHERE uid=$1", [uid]);
    if (existing.rows.length > 0) {
      logWarn(`[create-user] User already exists: ${uid}`);
      return res.status(400).json({ error: "User already exists" });
    }

    const result = await client.query(
      `INSERT INTO users(
        uid,
        email,
        password,
        display_name,
        bio,
        location,
        socials,
        payment_methods,
        user_type,
        wallet
      ) VALUES($1,$2,$3,$4,$5,$6,$7::jsonb,$8::jsonb,$9,$10)
      RETURNING *`,
      [
        uid,
        email,
        password || null,
        display_name || email.split("@")[0],
        bio,
        location || "",
        JSON.stringify(socials),
        JSON.stringify(payment_methods),
        user_type,
        wallet,
      ]
    );

    await updateLastActive(uid);
    log(`[create-user] User created successfully: ${uid}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[create-user] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});


app.post("/set-valid", async (req, res) => {
  const { uid } = req.body;

  if (!uid) return res.status(400).json({ error: "UID required" });

  try {
    await client.query(
      `UPDATE users SET is_valid = true WHERE uid = $1`,
      [uid]
    );
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});



app.post("/sign-in", async (req, res) => {
  const { email, password } = req.body;
  if (!email) return res.status(400).json({ error: "Email required" });

  try {
    log(`[sign-in] Signing in user: ${email}`);
    let result;
    if (password) {
      result = await client.query(
        `UPDATE users
         SET last_active = NOW()
         WHERE email = $1 AND password = $2
         RETURNING *`,
        [email, password]
      );
    } else {
      result = await client.query(
        `UPDATE users
         SET last_active = NOW()
         WHERE email = $1
         RETURNING *`,
        [email]
      );
    }

    if (result.rows.length === 0) {
      logWarn(`[sign-in] Invalid credentials for email: ${email}`);
      return res.status(401).json({ error: "Invalid credentials" });
    }

    log(`[sign-in] User signed in successfully: ${email}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[sign-in] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/users", async (req, res) => {
  const { location } = req.query;
  try {
    log(`[get-users] Fetching all users${location ? ` in ${location}` : ''}`);
    let query = "SELECT * FROM users";
    const params = [];

    if (location) {
      query += " WHERE LOWER(location) LIKE LOWER($1)";
      params.push(`%${location}%`);
    }

    const result = await client.query(query, params);
    log(`[get-users] Fetched ${result.rows.length} users`);
    res.json(result.rows);
  } catch (err) {
    logError(`[get-users] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/users/:uid", async (req, res) => {
  const { uid } = req.params;
  if (!uid) return res.status(400).json({ error: "User ID required" });

  try {
    log(`[get-user] Fetching user: ${uid}`);
    await updateLastActive(uid);
    const result = await client.query("SELECT * FROM users WHERE uid=$1", [uid]);
    if (result.rows.length === 0) {
      logWarn(`[get-user] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    log(`[get-user] User fetched: ${uid}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[get-user] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.patch("/users/:uid", async (req, res) => {
  const { uid } = req.params;
  const {
    display_name,
    email,
    bio,
    location,
    socials,
    payment_methods,
    user_type,
    wallet,
  } = req.body;

  if (!uid) return res.status(400).json({ error: "User ID required" });

  try {
    log(`[patch-user] Updating user: ${uid}`);
    await updateLastActive(uid);
    const result = await client.query(
      `UPDATE users
       SET display_name = COALESCE($1, display_name),
           email = COALESCE($2, email),
           bio = COALESCE($3, bio),
           location = COALESCE($4, location),
           socials = COALESCE($5::jsonb, socials),
           payment_methods = COALESCE($6::jsonb, payment_methods),
           user_type = COALESCE($7, user_type),
           wallet = COALESCE($8, wallet)
       WHERE uid = $9
       RETURNING *`,
      [
        display_name,
        email,
        bio,
        location,
        socials ? JSON.stringify(socials) : null,
        payment_methods ? JSON.stringify(payment_methods) : null,
        user_type,
        wallet,
        uid,
      ]
    );

    if (result.rows.length === 0) {
      logWarn(`[patch-user] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    log(`[patch-user] User updated: ${uid}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[patch-user] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.patch("/users/:uid/wallet", async (req, res) => {
  const { uid } = req.params;
  const { delta } = req.body;
  if (!uid || typeof delta !== "number") return res.status(400).json({ error: "UID and numeric delta required" });

  try {
    log(`[patch-wallet] Adjusting wallet for ${uid} by ${delta}`);
    await updateLastActive(uid);
    const result = await client.query(
      `UPDATE users
       SET wallet = wallet + $1
       WHERE uid = $2
       RETURNING *`,
      [delta, uid]
    );

    if (result.rows.length === 0) {
      logWarn(`[patch-wallet] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    log(`[patch-wallet] Wallet adjusted for ${uid}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[patch-wallet] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/revenue/:uid", async (req, res) => {
  const { uid } = req.params;
  if (!uid) return res.status(400).json({ error: "UID required" });

  try {
    log(`[get-revenue] Fetching revenue for ${uid}`);
    await updateLastActive(uid);
    const result = await client.query(
      "SELECT year, revenue FROM revenue WHERE uid = $1 ORDER BY year DESC",
      [uid]
    );
    log(`[get-revenue] Fetched ${result.rows.length} revenue records for ${uid}`);
    res.json(result.rows);
  } catch (err) {
    logError(`[get-revenue] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/revenue/:uid", async (req, res) => {
  const { uid } = req.params;
  const { year, revenue } = req.body;
  if (!uid || !year || revenue === undefined) return res.status(400).json({ error: "UID, year, and revenue required" });

  try {
    log(`[post-revenue] Setting revenue for ${uid}: year=${year}, revenue=${revenue}`);
    await updateLastActive(uid);
    const result = await client.query(
      `INSERT INTO revenue (uid, year, revenue)
       VALUES ($1, $2, $3)
       ON CONFLICT (uid, year) DO UPDATE SET revenue = $3
       RETURNING *`,
      [uid, year, revenue]
    );
    log(`[post-revenue] Revenue set for ${uid}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[post-revenue] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// -----------------------------
// --- JOB ENDPOINTS ---
// -----------------------------

app.get("/jobs", async (req, res) => {
  const { uid } = req.query;
  try {
    if (uid) await updateLastActive(uid);
    log(`[get-jobs] Fetching jobs${uid ? ` for user ${uid}` : ''}`);
    let query = "SELECT * FROM jobs";
    const params = [];
    if (uid) {
      query += " WHERE creator_uid = $1";
      params.push(uid);
    }
    const result = await client.query(query, params);
    log(`[get-jobs] Fetched ${result.rows.length} jobs`);
    res.json(result.rows);
  } catch (err) {
    logError(`[get-jobs] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/jobs/:id", async (req, res) => {
  const { id } = req.params;
  try {
    log(`[get-job] Fetching job ${id}`);
    const result = await client.query("SELECT * FROM jobs WHERE uid=$1", [id]);
    if (result.rows.length === 0) {
      logWarn(`[get-job] Job not found: ${id}`);
      return res.status(404).json({ error: "Job not found" });
    }
    log(`[get-job] Job fetched: ${id}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[get-job] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/jobs", async (req, res) => {
  const {
    title,
    description,
    budget,
    influencerCount,
    influenceMin,
    influenceMax,
    location,
    genre,
    creatorId,
    status,
    endDate,
    currency = "usd",
  } = req.body;

  if (!creatorId || !title || !description || !budget || !endDate) {
    return res.status(400).json({ error: "Missing required fields: creatorId, title, description, budget, endDate" });
  }

  try {
    log(`[post-job] Creating job: ${title} for creator ${creatorId}${location ? ` in ${location}` : ''}`);
    await updateLastActive(creatorId);

    const userResult = await client.query(
      "SELECT payment_methods, email, display_name FROM users WHERE uid=$1",
      [creatorId]
    );
    if (userResult.rows.length === 0) {
      logError(`[post-job] Creator not found: ${creatorId}`);
      return res.status(404).json({ error: "Creator not found" });
    }

    const user = userResult.rows[0];
    const paymentMethods = user.payment_methods || {};
    const stripeData = paymentMethods.stripe;

    if (!stripeData?.customerId || !stripeData?.paymentMethodId) {
      logWarn(`[post-job] Creator has no saved Stripe payment method: ${creatorId}`);
      return res.status(400).json({ error: "Creator has no saved Stripe payment method" });
    }

    log(`[post-job] Processing Stripe charge for ${budget} ${currency}`);
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(budget * 100),
      currency,
      customer: stripeData.customerId,
      payment_method: stripeData.paymentMethodId,
      off_session: true,
      confirm: true,
      description: `Job creation: ${title}`,
    });

    const result = await client.query(
      `INSERT INTO jobs(
         title, description, budget, influencer_slots, influence_min, influence_max,
         location, genre, creator_uid, status, created_at, end_date, stripe_charge_id
       ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,NOW(),$11,$12)
       RETURNING *`,
      [
        title,
        description,
        budget,
        influencerCount,
        influenceMin,
        influenceMax,
        location || "",
        genre,
        creatorId,
        status || "open",
        endDate,
        paymentIntent.id,
      ]
    );

    log(`[post-job] Job created successfully: ${result.rows[0].uid}`);
    res.json({ message: "Job created and charged successfully", job: result.rows[0], paymentIntent });
  } catch (err) {
    logError(`[post-job] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/jobs/:id/claim", async (req, res) => {
  const { id } = req.params;
  const { userId } = req.body;

  if (!userId) return res.status(400).json({ error: "userId required" });

  try {
    log(`[claim-job] User ${userId} claiming job ${id}`);
    await updateLastActive(userId);

    const jobResult = await client.query("SELECT * FROM jobs WHERE uid=$1", [id]);
    if (jobResult.rows.length === 0) {
      logWarn(`[claim-job] Job not found: ${id}`);
      return res.status(404).json({ error: "Job not found" });
    }

    const job = jobResult.rows[0];

    const maxSlots = Number(job.max_slots);
    const budget = Number(job.budget);
    const influencerSlots = typeof job.influencer_slots === "number"
      ? job.influencer_slots
      : maxSlots;

    if (isNaN(maxSlots) || maxSlots <= 0 || isNaN(budget) || budget <= 0) {
      logError(`[claim-job] Invalid job configuration for job ${id}`);
      return res.status(400).json({ error: "Invalid job configuration: max_slots or budget missing" });
    }

    if (influencerSlots <= 0) {
      logWarn(`[claim-job] All influencer slots claimed for job ${id}`);
      return res.status(400).json({ error: "All influencer slots are already claimed" });
    }

    log(`[claim-job] maxSlots: ${maxSlots}, budget: ${budget}, remainingSlots: ${influencerSlots}`);

    const perInfluencerAmount = Number(((1 - __cutRate) * budget / maxSlots).toFixed(2));

    await client.query(
      `INSERT INTO influencer_jobs (user_uid, job_uid, closed_at, amount)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT DO NOTHING`,
      [userId, id, job.closed_at, perInfluencerAmount]
    );

    await client.query(
      `UPDATE jobs
       SET influencer_slots = GREATEST(COALESCE(influencer_slots, 0) - 1, 0)
       WHERE uid=$1`,
      [id]
    );

    log(`[claim-job] Job claimed successfully by ${userId}`);
    res.json({
      status: "claimed",
      amount: perInfluencerAmount,
      remainingSlots: influencerSlots - 1,
    });
  } catch (err) {
    logError(`[claim-job] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/influencer-jobs/user/:uid", async (req, res) => {
  const { uid } = req.params;
  if (!uid) return res.status(400).json({ error: "UID required" });

  try {
    log(`[get-influencer-jobs] Fetching influencer jobs for user ${uid}`);
    await updateLastActive(uid);

    const result = await client.query(
      `SELECT ij.*, j.title, j.end_date
       FROM influencer_jobs ij
       JOIN jobs j ON ij.job_uid = j.uid
       WHERE ij.user_uid = $1
       ORDER BY ij.assigned_at DESC`,
      [uid]
    );

    log(`[get-influencer-jobs] Fetched ${result.rows.length} influencer jobs for ${uid}`);
    res.json(result.rows);
  } catch (err) {
    logError(`[get-influencer-jobs] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/influencer-jobs/job/:jobUid", async (req, res) => {
  const { jobUid } = req.params;

  if (!jobUid) return res.status(400).json({ error: "jobUid required" });

  try {
    log(`[get-influencers-by-job] Fetching influencers for job ${jobUid}`);
    const result = await client.query(
      `SELECT ij.user_uid, u.display_name, ij.content_approved_at, ij.content_done_at
       FROM influencer_jobs ij
       JOIN users u ON ij.user_uid = u.uid
       WHERE ij.job_uid = $1
       ORDER BY ij.assigned_at DESC`,
      [jobUid]
    );

    const mapped = result.rows.map((row) => ({
      uid: row.user_uid,
      displayName: row.display_name,
      completed: !!row.content_approved_at,
      content_done_at: !!row.content_done_at,
    }));

    log(`[get-influencers-by-job] Fetched ${mapped.length} influencers for job ${jobUid}`);
    res.json(mapped);
  } catch (err) {
    logError(`[get-influencers-by-job] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});



app.post("/jobs/:id/close", async (req, res) => {
  const { id } = req.params;

  if (!id) return res.status(400).json({ error: "Job ID required" });

  try {
    log(`[close-job] Closing job ${id}`);
    const result = await client.query(
      `UPDATE jobs
       SET closed_at = NOW(),
           status = 'closed'
       WHERE uid = $1
       RETURNING *`,
      [id]
    );

    if (result.rows.length === 0) {
      logWarn(`[close-job] Job not found: ${id}`);
      return res.status(404).json({ error: "Job not found" });
    }

    log(`[close-job] Job closed successfully: ${id}`);
    res.json({ message: "Job manually closed", job: result.rows[0] });
  } catch (err) {
    logError(`[close-job] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET endpoint to read all content submissions
app.get("/content/submissions", async (req, res) => {
  const { jobUid, userUid, status, limit = 50, offset = 0 } = req.query;
  
  try {
    log("[get-submissions] Fetching content submissions");
    
    let query = `SELECT * FROM content_submissions WHERE 1=1`;
    const params = [];
    let paramCount = 1;
    
    if (jobUid) {
      query += ` AND job_uid = $${paramCount}`;
      params.push(jobUid);
      paramCount++;
    }
    
    if (userUid) {
      query += ` AND influencer_uid = $${paramCount}`;
      params.push(userUid);
      paramCount++;
    }
    
    if (status === "approved") {
      query += ` AND approved_at IS NOT NULL`;
    } else if (status === "rejected") {
      query += ` AND rejected_at IS NOT NULL`;
    } else if (status === "pending") {
      query += ` AND approved_at IS NULL AND rejected_at IS NULL`;
    }
    
    query += ` ORDER BY submitted_at DESC LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
    params.push(limit, offset);
    
    const result = await client.query(query, params);
    
    log(`[get-submissions] Retrieved ${result.rows.length} submissions`);
    res.json({
      submissions: result.rows,
      count: result.rows.length,
      limit,
      offset,
    });
  } catch (err) {
    logError(`[get-submissions] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET endpoint to read a single submission
app.get("/content/submissions/:submissionId", async (req, res) => {
  const { submissionId } = req.params;
  
  try {
    log(`[get-submission] Fetching submission ${submissionId}`);
    
    const result = await client.query(
      `SELECT * FROM content_submissions WHERE id = $1`,
      [submissionId]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "Submission not found" });
    }
    
    log(`[get-submission] Retrieved submission ${submissionId}`);
    res.json({ submission: result.rows[0] });
  } catch (err) {
    logError(`[get-submission] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// PATCH endpoint to approve or reject a submission
app.patch("/content/submissions/:submissionUid/review", async (req, res) => {
  const { submissionUid } = req.params;
  const { action } = req.body;
  if (!action || !["approve", "reject"].includes(action)) {
    return res.status(400).json({
      error: "action must be either 'approve' or 'reject'",
    });
  }
  try {
    log(`[review-submission] ${action === "approve" ? "Approving" : "Rejecting"} submission ${submissionUid}`);
    // Check if submission exists
    const checkResult = await client.query(
      `SELECT * FROM content_submissions WHERE uid = $1`,
      [submissionUid]
    );
    if (checkResult.rows.length === 0) {
      return res.status(404).json({ error: "Submission not found" });
    }
    const submission = checkResult.rows[0];
    let updateQuery;
    const params = [submissionUid];
    if (action === "approve") {
      updateQuery = `
        UPDATE content_submissions
        SET approved_at = NOW(), rejected_at = NULL
        WHERE uid = $1
        RETURNING *
      `;
    } else {
      updateQuery = `
        UPDATE content_submissions
        SET rejected_at = NOW(), approved_at = NULL
        WHERE uid = $1
        RETURNING *
      `;
    }
    const result = await client.query(updateQuery, params);
    const updatedSubmission = result.rows[0];
    
    // Check if submission was previously approved/rejected for backwards compatibility
    const wasApproved = !!checkResult.rows[0].approved_at;
    const wasRejected = !!checkResult.rows[0].rejected_at;
    
    // Update jobs table based on action
    if (action === "approve") {
      // Only increment if it wasn't already approved (backwards compatibility)
      if (!wasApproved) {
        log(`[review-submission] Incrementing approved for job ${submission.job_uid}`);
        await client.query(
          `UPDATE jobs
           SET approved = COALESCE(approved, 0) + 1
           WHERE uid = $1`,
          [submission.job_uid]
        );
      } else {
        log(`[review-submission] Submission was already approved, skipping increment for job ${submission.job_uid}`);
      }
    } else if (action === "reject") {
      // If it was previously approved, decrement. If it was pending, don't change count
      if (wasApproved) {
        log(`[review-submission] Decrementing approved for job ${submission.job_uid} (was previously approved)`);
        await client.query(
          `UPDATE jobs
           SET approved = GREATEST(COALESCE(approved, 0) - 1, 0)
           WHERE uid = $1`,
          [submission.job_uid]
        );
      } else if (!wasRejected) {
        log(`[review-submission] Submission was pending, no count change for job ${submission.job_uid}`);
      } else {
        log(`[review-submission] Submission was already rejected, skipping for job ${submission.job_uid}`);
      }
    }
    
    log(`[review-submission] Submission ${submissionUid} ${action === "approve" ? "approved" : "rejected"}`);
    res.json({
      message: `Submission ${action === "approve" ? "approved" : "rejected"} successfully`,
      submission: updatedSubmission,
    });
  } catch (err) {
    logError(`[review-submission] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});


// DELETE endpoint to remove an influencer from a campaign
app.delete("/jobs/:jobUid/influencers/:influencerUid", async (req, res) => {
  const { jobUid, influencerUid } = req.params;
  const { artistUid } = req.body;

  if (!jobUid || !influencerUid || !artistUid) {
    return res.status(400).json({
      error: "jobUid, influencerUid, and artistUid are required",
    });
  }

  try {
    log(`[remove-influencer] Artist ${artistUid} removing influencer ${influencerUid} from job ${jobUid}`);
    await updateLastActive(artistUid);

    // Verify the artist owns this job
    const jobResult = await client.query(
      `SELECT * FROM jobs WHERE uid = $1 AND creator_uid = $2`,
      [jobUid, artistUid]
    );

    if (jobResult.rows.length === 0) {
      logWarn(`[remove-influencer] Job not found or artist is not the creator: ${jobUid}`);
      return res.status(403).json({
        error: "You do not have permission to remove influencers from this job",
      });
    }

    // Get the influencer job record to retrieve the amount
    const influencerJobResult = await client.query(
      `SELECT * FROM influencer_jobs WHERE job_uid = $1 AND user_uid = $2`,
      [jobUid, influencerUid]
    );

    if (influencerJobResult.rows.length === 0) {
      logWarn(`[remove-influencer] Influencer job not found: ${jobUid}, ${influencerUid}`);
      return res.status(404).json({
        error: "Influencer is not assigned to this job",
      });
    }

    const influencerJob = influencerJobResult.rows[0];
    const refundAmount = influencerJob.amount || 0;

    // Delete the influencer_jobs entry
    log(`[remove-influencer] Deleting influencer_jobs record for ${influencerUid}`);
    await client.query(
      `DELETE FROM influencer_jobs WHERE job_uid = $1 AND user_uid = $2`,
      [jobUid, influencerUid]
    );

    // Restore the influencer slot
    log(`[remove-influencer] Incrementing available slots for job ${jobUid}`);
    await client.query(
      `UPDATE jobs
       SET influencer_slots = COALESCE(influencer_slots, 0) + 1
       WHERE uid = $1`,
      [jobUid]
    );

    log(`[remove-influencer] Influencer ${influencerUid} removed from job ${jobUid}`);
    res.json({
      message: "Influencer removed from campaign",
      removedInfluencer: influencerUid,
      slotsNowAvailable: true,
    });
  } catch (err) {
    logError(`[remove-influencer] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});


app.post("/content/submit", async (req, res) => {
  const {
    jobUid,
    userUid,
    mediaUrl,
    mediaType,
    fileName,
    fileSize,
    mimeType,
    durationSec,
    resolution,
  } = req.body;

  log(`[submit-content] Received request - jobUid: ${jobUid}, userUid: ${userUid}`);

  // Validate required fields
  if (!jobUid || !userUid || !mediaUrl || !mediaType) {
    return res.status(400).json({
      error: "jobUid, userUid, mediaUrl, and mediaType are required",
    });
  }

  try {
    log(`[submit-content] User ${userUid} submitting content for job ${jobUid}`);
    await updateLastActive(userUid);

    // Insert content submission
    log(`[submit-content] Inserting into content_submissions table`);
    const result = await client.query(
      `INSERT INTO content_submissions (
         job_uid, influencer_uid, media_url, media_type,
         file_name, file_size, mime_type, duration_sec, resolution, submitted_at
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
       RETURNING *`,
      [
        jobUid,            // $1 - job_uid
        userUid,           // $2 - influencer_uid
        mediaUrl,          // $3 - media_url
        mediaType,         // $4 - media_type
        fileName || null,  // $5 - file_name
        fileSize || null,  // $6 - file_size
        mimeType || null,  // $7 - mime_type
        durationSec || null, // $8 - duration_sec
        resolution || null,  // $9 - resolution
      ]
    );

    log(`[submit-content] Content inserted successfully`);

    // Update influencer job to mark content as done
    log(`[submit-content] Updating influencer_jobs table`);
    await client.query(
      `UPDATE influencer_jobs
       SET content_done_at = NOW()
       WHERE job_uid = $1 AND user_uid = $2`,
      [jobUid, userUid]
    );

    log(`[submit-content] Content submitted successfully for user ${userUid} on job ${jobUid}`);

    res.json({
      message: "Content submitted successfully",
      submission: result.rows[0],
    });
  } catch (err) {
    logError(`[submit-content] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});




// app.post("/influencer-jobs/:claimUid/influencerComplete", async (req, res) => {
//   const { claimUid } = req.params;
//   const { userUid } = req.body;

//   if (!claimUid || !userUid) {
//     return res.status(400).json({ error: "claimUid and userUid required" });
//   }

//   try {
//     log(`[mark-job-done] Marking claim ${claimUid} as done for user ${userUid}`);
//     await updateLastActive(userUid);

//     const result = await client.query(
//       `SELECT ij.*, j.title
//        FROM influencer_jobs ij
//        JOIN jobs j ON ij.job_uid = j.uid
//        WHERE ij.uid=$1 AND ij.user_uid=$2`,
//       [claimUid, userUid]
//     );

//     if (result.rows.length === 0) {
//       logWarn(`[mark-job-done] Claim not found: ${claimUid} for user ${userUid}`);
//       return res.status(404).json({ error: "Claim not found for this user" });
//     }

//     const updateResult = await client.query(
//       `UPDATE influencer_jobs
//        SET content_done_at = NOW()
//        WHERE uid=$1 AND user_uid=$2
//        RETURNING *,
//                  (SELECT title FROM jobs WHERE uid=job_uid) AS title`,
//       [claimUid, userUid]
//     );

//     log(`[mark-job-done] Job marked as complete: ${claimUid}`);
//     res.json({ message: "Job marked as complete", job: updateResult.rows[0] });
//   } catch (err) {
//     logError(`[mark-job-done] Error:`, err.message);
//     res.status(500).json({ error: err.message });
//   }
// });




// -----------------------------
// --- ESCROW ENDPOINTS ---
// -----------------------------

app.post("/escrow", async (req, res) => {
  const { buyer_id, seller_id, payment_amount } = req.body;
  if (!buyer_id || !seller_id || !payment_amount) return res.status(400).json({ error: "Missing required fields" });

  const escrow_id = uuidv4();
  try {
    log(`[create-escrow] Creating escrow: ${escrow_id}`);
    await updateLastActive(buyer_id);
    await updateLastActive(seller_id);

    await client.query(
      `INSERT INTO escrow_transactions(escrow_id, buyer_id, seller_id, payment_amount)
       VALUES($1,$2,$3,$4)`,
      [escrow_id, buyer_id, seller_id, payment_amount]
    );
    log(`[create-escrow] Escrow created: ${escrow_id}`);
    res.json({ escrow_id, status: "pending" });
  } catch (err) {
    logError(`[create-escrow] Error:`, err.message);
    res.status(400).json({ error: err.message });
  }
});

app.get("/escrow", async (_req, res) => {
  try {
    log(`[get-escrow] Fetching all escrow transactions`);
    const result = await client.query("SELECT * FROM escrow_transactions ORDER BY payment_time DESC");
    log(`[get-escrow] Fetched ${result.rows.length} escrow transactions`);
    res.json(result.rows);
  } catch (err) {
    logError(`[get-escrow] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.patch("/escrow/:escrow_id/status", async (req, res) => {
  const { escrow_id } = req.params;
  const { status } = req.body;
  if (!status) return res.status(400).json({ error: "Status required" });

  try {
    log(`[patch-escrow] Updating escrow ${escrow_id} to status: ${status}`);
    const result = await client.query(
      `UPDATE escrow_transactions
       SET status=$1,
           escrow_released_time=CASE WHEN $1='released' THEN NOW() ELSE escrow_released_time END
       WHERE escrow_id=$2
       RETURNING *`,
      [status, escrow_id]
    );

    if (result.rows.length === 0) {
      logWarn(`[patch-escrow] Escrow not found: ${escrow_id}`);
      return res.status(404).json({ error: "Escrow not found" });
    }
    log(`[patch-escrow] Escrow updated: ${escrow_id}`);
    res.json(result.rows[0]);
  } catch (err) {
    logError(`[patch-escrow] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

// --------------------------------
// STRIPE 
// --------------------------------

app.post("/stripe/create-customer", async (req, res) => {
  const { uid, email, name } = req.body;
  if (!uid || !email) return res.status(400).json({ error: "UID and email required" });

  try {
    log(`[Stripe] Creating customer for UID: ${uid}`);
    await updateLastActive(uid);

    const userResult = await client.query("SELECT * FROM users WHERE uid=$1", [uid]);
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    const user = userResult.rows[0];

    const customer = await stripe.customers.create({ email, name, metadata: { uid } });

    const paymentMethods = user.payment_methods || {};
    paymentMethods.stripe = { customerId: customer.id, paymentMethodId: null };

    const updated = await client.query(
      "UPDATE users SET payment_methods=$1::jsonb WHERE uid=$2 RETURNING *",
      [JSON.stringify(paymentMethods), uid]
    );

    log(`[Stripe] Customer created: ${customer.id}`);
    res.json({ message: "Stripe customer created", stripeCustomerId: customer.id, user: updated.rows[0] });
  } catch (err) {
    logError(`[Stripe] Error creating customer:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/add-payment-method", async (req, res) => {
  const { uid, paymentMethodId } = req.body;
  if (!uid || !paymentMethodId) return res.status(400).json({ error: "UID and paymentMethodId required" });

  try {
    log(`[Stripe] Attaching payment method for UID: ${uid}`);
    await updateLastActive(uid);

    const userResult = await client.query("SELECT payment_methods, email, display_name FROM users WHERE uid=$1", [uid]);
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }

    const user = userResult.rows[0];
    const paymentMethods = user.payment_methods || {};
    if (!paymentMethods.stripe) paymentMethods.stripe = {};

    let customerId = paymentMethods.stripe.customerId;
    if (!customerId) {
      log(`[Stripe] Creating new customer for ${uid}`);
      const customer = await stripe.customers.create({
        email: user.email,
        name: user.display_name,
        metadata: { uid },
      });
      customerId = customer.id;
      paymentMethods.stripe.customerId = customerId;
    }

    log(`[Stripe] Attaching payment method ${paymentMethodId} to customer ${customerId}`);
    const attachRes = await stripe.paymentMethods.attach(paymentMethodId, { customer: customerId });

    await stripe.customers.update(customerId, { invoice_settings: { default_payment_method: attachRes.id } });

    paymentMethods.stripe.paymentMethodId = attachRes.id;
    await client.query("UPDATE users SET payment_methods=$1::jsonb WHERE uid=$2", [
      JSON.stringify(paymentMethods),
      uid,
    ]);

    log(`[Stripe] Payment method attached successfully`);
    res.json({ message: "Payment method attached", paymentMethod: attachRes });
  } catch (err) {
    logError(`[Stripe] Error attaching payment method:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/update-payment-method", async (req, res) => {
  const { uid, paymentMethodId, billingDetails } = req.body;
  if (!uid || !paymentMethodId) return res.status(400).json({ error: "UID and paymentMethodId required" });

  try {
    log(`[Stripe] Updating payment method for UID: ${uid}`);
    await updateLastActive(uid);

    const userResult = await client.query("SELECT payment_methods FROM users WHERE uid=$1", [uid]);
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }

    const paymentMethods = userResult.rows[0].payment_methods || {};
    if (!paymentMethods.stripe || !paymentMethods.stripe.customerId) {
      logWarn(`[Stripe] Stripe customer not found for ${uid}`);
      return res.status(400).json({ error: "Stripe customer not found" });
    }

    const customerId = paymentMethods.stripe.customerId;
    const oldPaymentMethodId = paymentMethods.stripe.paymentMethodId;

    const updatedPaymentMethod = await stripe.paymentMethods.update(paymentMethodId, {
      billing_details: billingDetails || {},
    });

    if (oldPaymentMethodId && oldPaymentMethodId !== paymentMethodId) {
      log(`[Stripe] Detaching old payment method ${oldPaymentMethodId}`);
      await stripe.paymentMethods.detach(oldPaymentMethodId);
    }

    await stripe.customers.update(customerId, { invoice_settings: { default_payment_method: updatedPaymentMethod.id } });

    paymentMethods.stripe.paymentMethodId = updatedPaymentMethod.id;
    await client.query("UPDATE users SET payment_methods=$1::jsonb WHERE uid=$2", [
      JSON.stringify(paymentMethods),
      uid,
    ]);

    log(`[Stripe] Payment method updated successfully`);
    res.json({ message: "Payment method updated", paymentMethod: updatedPaymentMethod });
  } catch (err) {
    logError(`[Stripe] Error updating payment method:`, err.message);
    res.status(500).json({ error: err.message });
  }
});
app.post("/stripe/charge", async (req, res) => {
  const { uid, amount, currency, description } = req.body;
  if (!uid || !amount) return res.status(400).json({ error: "UID and amount required" });
  try {
    log(`[Stripe] Charging user: ${uid}, Amount: ${amount}, Currency: ${currency || 'usd'}`);
    await updateLastActive(uid);
    
    const userResult = await client.query("SELECT payment_methods FROM users WHERE uid=$1", [uid]);
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    
    let paymentMethods = userResult.rows[0].payment_methods;
    if (typeof paymentMethods === "string") {
      try {
        paymentMethods = JSON.parse(paymentMethods);
      } catch (e) {
        paymentMethods = {};
      }
    }
    if (!paymentMethods) paymentMethods = {};
    
    if (!paymentMethods.stripe?.customerId || !paymentMethods.stripe?.paymentMethodId) {
      logWarn(`[Stripe] Stripe customer/payment method not set up for ${uid}`);
      return res.status(400).json({ error: "Stripe customer/payment method not set up" });
    }
    
    // Verify stripe key is loaded
    if (!process.env.STRIPE_SECRET_KEY) {
      logError(`[Stripe] STRIPE_SECRET_KEY not found in environment variables`);
      return res.status(500).json({ error: "Server configuration error" });
    }
    
    // Create payment intent using platform account secret key
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(amount * 100),
      currency: currency || "usd",
      customer: paymentMethods.stripe.customerId,
      payment_method: paymentMethods.stripe.paymentMethodId,
      off_session: true,
      confirm: true,
      description: description || `Charge for ${uid}`,
    });
    
    log(`[Stripe] Charge successful: ${paymentIntent.id}, Amount: ${amount}`);
    
    res.json({ 
      message: "Payment successful", 
      paymentIntent,
      fundsReceivedToAccount: true 
    });
  } catch (err) {
    logError(`[Stripe] Charge failed:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/refund", async (req, res) => {
  const { paymentIntentId, amount } = req.body;

  if (!paymentIntentId)
    return res.status(400).json({ error: "paymentIntentId required" });

  try {
    log(`[Stripe] Creating refund for payment intent: ${paymentIntentId}`);
    const refund = await stripe.refunds.create({
      payment_intent: paymentIntentId,
      amount: amount ? Math.round(amount * 100) : undefined,
    });

    log(`[Stripe] Refund successful: ${refund.id}`);
    res.json({ message: "Refund successful", refund });
  } catch (err) {
    logError(`[Stripe] Refund failed:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/connect/create", async (req, res) => {
  const { uid, email, name } = req.body;
  log(`[Stripe Connect] Creating account - UID: ${uid}, Email: ${email}`);

  if (!uid || !email)
    return res.status(400).json({ error: "UID and email required" });

  try {
    await updateLastActive(uid);

    const userResult = await client.query(
      "SELECT payment_methods FROM users WHERE uid=$1",
      [uid]
    );
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe Connect] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }

    let paymentMethods = userResult.rows[0].payment_methods || {};
    let connectAccountId = paymentMethods?.stripe?.connectAccountId;

    if (connectAccountId) {
      log(`[Stripe Connect] Existing account found: ${connectAccountId}`);
      return res.json({
        message: "Connect account already exists",
        connectAccountId,
      });
    }

    log(`[Stripe Connect] Creating new Express account for ${uid}`);
    const account = await stripe.accounts.create({
      type: "express",
      country: "US",
      email,
      business_type: "individual",
      business_profile: { mcc: "5734", name },
      capabilities: {
        card_payments: { requested: true },
        transfers: { requested: true },
      },
    });

    log(`[Stripe Connect] Account created: ${account.id}`);

    paymentMethods = {
      ...paymentMethods,
      stripe: {
        ...(paymentMethods.stripe || {}),
        connectAccountId: account.id,
      },
    };

    await client.query(
      "UPDATE users SET payment_methods=$1::jsonb WHERE uid=$2",
      [JSON.stringify(paymentMethods), uid]
    );

    res.json({ message: "Connect account created", connectAccountId: account.id });
  } catch (err) {
    logError(`[Stripe Connect] Error creating account:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/connect/onboard", async (req, res) => {
  const { uid, refresh_url, return_url } = req.body;
  log(`[Stripe Connect] Generating onboarding link for UID: ${uid}`);

  if (!uid || !refresh_url || !return_url)
    return res.status(400).json({ error: "UID, refresh_url, and return_url required" });

  try {
    await updateLastActive(uid);

    const userResult = await client.query(
      "SELECT payment_methods FROM users WHERE uid=$1",
      [uid]
    );
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe Connect] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }

    const paymentMethods = userResult.rows[0].payment_methods || {};
    const connectAccountId = paymentMethods?.stripe?.connectAccountId;

    log(`[Stripe Connect] Using account: ${connectAccountId}`);

    if (!connectAccountId) {
      logWarn(`[Stripe Connect] Stripe Connect account not created yet for ${uid}`);
      return res.status(400).json({ error: "Stripe Connect account not created yet" });
    }

    const link = await stripe.accountLinks.create({
      account: connectAccountId,
      refresh_url,
      return_url,
      type: "account_onboarding",
    });

    log(`[Stripe Connect] Onboarding link created: ${link.url}`);
    res.json({ onboardingUrl: link.url });
  } catch (err) {
    logError(`[Stripe Connect] Error generating onboarding link:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post("/stripe/connect/payout", async (req, res) => {
  const { uid, amount, currency = "usd" } = req.body;
  log(`[Stripe Connect] Initiating payout - UID: ${uid}, Amount: ${amount}`);

  if (!uid || !amount)
    return res.status(400).json({ error: "UID and amount required" });

  try {
    await updateLastActive(uid);

    const userResult = await client.query(
      "SELECT payment_methods, wallet FROM users WHERE uid=$1",
      [uid]
    );
    if (userResult.rows.length === 0) {
      logWarn(`[Stripe Connect] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }

    const user = userResult.rows[0];
    const connectAccountId = user.payment_methods?.stripe?.connectAccountId;

    log(`[Stripe Connect] Using account: ${connectAccountId}`);

    if (!connectAccountId) {
      logWarn(`[Stripe Connect] Connect account not set up for ${uid}`);
      return res.status(400).json({ error: "Connect account not set up" });
    }

    if (user.wallet < amount) {
      logWarn(`[Stripe Connect] Insufficient wallet balance for ${uid}: ${user.wallet} < ${amount}`);
      return res.status(400).json({ error: "Insufficient wallet balance" });
    }

    // Ensure transfers capability is enabled
    log(`[Stripe Connect] Ensuring transfers capability for ${connectAccountId}`);
    await stripe.accounts.update(connectAccountId, {
      capabilities: {
        transfers: { requested: true },
      },
    });

    const transfer = await stripe.transfers.create({
      amount: Math.round(amount * 100),
      currency,
      destination: connectAccountId,
    });

    await client.query(
      "UPDATE users SET wallet = wallet - $1 WHERE uid=$2",
      [amount, uid]
    );

    log(`[Stripe Connect] Payout successful: ${transfer.id}`);
    res.json({ message: "Payout successful", transfer });
  } catch (err) {
    logError(`[Stripe Connect] Error processing payout:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get('/stripe/complete', (req, res) => {
  log(`[Stripe] Stripe setup complete page accessed`);
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Setup Complete</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          margin: 0;
          background: #f5f5f5;
          text-align: center;
          padding: 20px;
        }
        .container {
          background: white;
          padding: 40px;
          border-radius: 12px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #00D924; margin: 0 0 10px 0; }
        p { color: #666; margin: 10px 0; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>✅ Withdrawal Setup Complete!</h1>
        <p>Your bank account has been connected.</p>
        <p><strong>Please return to the app to continue.</strong></p>
      </div>
      <script>
        setTimeout(() => window.close(), 3000);
      </script>
    </body>
    </html>
  `);
});
app.post("/withdraw", async (req, res) => {
  const { uid, amount, currency = "usd" } = req.body;
  log(`[Withdraw] Initiated - UID: ${uid}, Amount: ${amount}, Currency: ${currency}`);

  if (!uid || !amount) {
    return res.status(400).json({ error: "UID and amount required" });
  }
  if (typeof amount !== "number" || amount <= 0) {
    return res.status(400).json({ error: "Amount must be a positive number" });
  }

  try {
    await updateLastActive(uid);

    // 1️⃣ Fetch user data
    const userResult = await client.query(
      "SELECT wallet, payment_methods FROM users WHERE uid=$1",
      [uid]
    );
    if (userResult.rows.length === 0) {
      logWarn(`[Withdraw] User not found: ${uid}`);
      return res.status(404).json({ error: "User not found" });
    }
    const user = userResult.rows[0];
    const wallet = Number(user.wallet);

    if (wallet < amount) {
      logWarn(`[Withdraw] Insufficient balance for ${uid}: ${wallet} < ${amount}`);
      return res.status(400).json({ error: "Insufficient wallet balance", available: wallet, requested: amount });
    }

    // 2️⃣ Parse payment_methods
    let paymentMethods = user.payment_methods;
    if (typeof paymentMethods === "string") {
      try { paymentMethods = JSON.parse(paymentMethods); } catch { paymentMethods = {}; }
    }
    const connectAccountId = paymentMethods?.stripe?.connectAccountId;
    if (!connectAccountId) {
      logWarn(`[Withdraw] No Stripe Connect account for ${uid}`);
      return res.status(400).json({ error: "Stripe Connect account not set up. Complete onboarding first." });
    }

    log(`[Withdraw] Using Connect account: ${connectAccountId}`);

    // 3️⃣ Create transfer from platform → connected account
    let transfer;
    try {
      transfer = await stripe.transfers.create({
        amount: Math.round(amount * 100),
        currency,
        destination: connectAccountId,
        description: `Withdrawal for ${uid}`,
      });
      log(`[Withdraw] Transfer created: ${transfer.id}`);
    } catch (err) {
      logError(`[Withdraw] Transfer failed:`, err.message);
      return res.status(400).json({ error: "Failed to process withdrawal: " + err.message });
    }

    // 4️⃣ Deduct wallet balance
    await client.query("UPDATE users SET wallet = wallet - $1 WHERE uid=$2", [amount, uid]);
    log(`[Withdraw] Wallet debited for ${uid}: -${amount}`);

    // 5️⃣ Return success
    res.json({
      success: true,
      withdrawal: {
        type: "transfer",
        transferId: transfer.id,
        status: transfer.status || "completed",
        destination: "Stripe Connect account",
        message: `$${amount} transferred to your Stripe account. It will arrive in your bank based on your payout schedule.`,
      },
      newWalletBalance: wallet - amount,
    });

  } catch (err) {
    logError(`[Withdraw] Error:`, err.message);
    res.status(500).json({ error: err.message });
  }
});


// -----------------------------
// --- MANUAL JOB CLOSER ---
// -----------------------------
app.post('/worker/manualJobCloser', async (req, res) => {
  try {
    await runManualJobCloser();
    res.status(200).send({ message: 'Manual job closer completed.' });
  } catch (err) {
    console.error(`[JobCloser] Fatal error in endpoint:`, err);
    res.status(500).send({ error: err.message });
  }
});

const runManualJobCloser = async () => {
  log(`[JobCloser] Manual job closer started`);

  try {
    const jobsResult = await client.query(`
      SELECT uid, end_date
      FROM jobs
      WHERE status = 'open' AND end_date::date <= NOW()::date
    `);
    log(`[JobCloser] Fetched ${jobsResult.rowCount} job(s) to close`);

    for (const row of jobsResult.rows) {
      log(`[JobCloser] Processing job: uid=${row.uid}, end_date=${row.end_date}`);

      try {
        const updateResult = await client.query(`
          UPDATE jobs
          SET status = 'closed', closed_at = NOW()
          WHERE uid = $1
        `, [row.uid]);

        if (updateResult.rowCount === 1) {
          log(`[JobCloser] Job ${row.uid} closed successfully`);
        } else {
          logError(`[JobCloser] Database update affected ${updateResult.rowCount} rows for uid=${row.uid}`);
        }
      } catch (dbErr) {
        logError(`[JobCloser] Failed to close job ${row.uid}:`, dbErr);
      }
    }

  } catch (err) {
    logError(`[JobCloser] Error processing job closer:`, err);
  }

  log(`[JobCloser] Manual job closer finished`);
};

// -----------------------------
// --- MANUAL REFUND WORKER ----
// -----------------------------
app.post('/worker/manualRefund', async (req, res) => {
  try {
    await runManualRefundWorker();
    res.status(200).send({ message: 'Manual refund worker completed.' });
  } catch (err) {
    console.error(`[ManualWorker] Fatal error in endpoint:`, err);
    res.status(500).send({ error: err.message });
  }
});

const runManualRefundWorker = async () => {
  log(`[ManualWorker] Manual refund worker started`);

  try {
    const refundsResult = await client.query(`
      SELECT uid, job_uid, refunded, stripe_charge_id
      FROM unfilled_refunds
      WHERE stripe_charge_id IS NOT NULL AND stripe_refund_id IS NULL
    `);
    log(`[ManualWorker] Fetched ${refundsResult.rowCount} pending refund(s)`);

    for (const row of refundsResult.rows) {
      log(`[ManualWorker] Processing refund row: uid=${row.uid}, job_uid=${row.job_uid}, refunded=${row.refunded}, stripe_charge_id=${row.stripe_charge_id}`);

      const amountToRefund = Number(row.refunded);
      if (amountToRefund <= 0) {
        logWarn(`[ManualWorker] Skipping row ${row.uid} — refund amount is 0 or negative`);
        continue;
      }

      try {
        log(`[ManualWorker] Attempting Stripe refund: payment_intent=${row.stripe_charge_id}, amount=${amountToRefund}`);

        const refund = await stripe.refunds.create({
          payment_intent: row.stripe_charge_id,
          amount: Math.round(amountToRefund * 100),
        });

        log(`[ManualWorker] Stripe refund response: id=${refund.id}, status=${refund.status}, amount=${refund.amount}`);

        if (!refund.id) {
          logError(`[ManualWorker] Refund created but no refund ID returned for row ${row.uid}`);
          continue;
        }

        try {
          const updateResult = await client.query(`
            UPDATE unfilled_refunds
            SET stripe_refund_id = $1, issued_at = NOW()
            WHERE uid = $2
          `, [refund.id, row.uid]);

          if (updateResult.rowCount === 1) {
            log(`[ManualWorker] Database updated successfully for row ${row.uid}`);
          } else {
            logError(`[ManualWorker] Database update affected ${updateResult.rowCount} rows for uid=${row.uid}`);
          }
        } catch (dbErr) {
          logError(`[ManualWorker] Failed to update unfilled_refunds for row ${row.uid}:`, dbErr);
        }

        if (refund.status === 'succeeded') {
          log(`[ManualWorker] Refund succeeded for row ${row.uid}, amount=${amountToRefund}`);
        } else {
          logWarn(`[ManualWorker] Refund created but status is ${refund.status} for row ${row.uid}`);
        }

      } catch (stripeErr) {
        logError(`[ManualWorker] Stripe refund failed for row ${row.uid}:`, stripeErr);
      }
    }

  } catch (err) {
    logError(`[ManualWorker] Error processing manual refunds:`, err);
  }

  log(`[ManualWorker] Manual refund worker finished`);
};


// --------------------------------
// --- MANUAL ANALYTICS WORKER ---
// --------------------------------
app.post('/worker/manualAnalytics', async (req, res) => {
  try {
    await runManualAnalyticsWorker();
    res.status(200).send({ message: 'Manual analytics worker completed.' });
  } catch (err) {
    console.error(`[AnalyticsWorker] Fatal error in endpoint:`, err);
    res.status(500).send({ error: err.message });
  }
});

const runManualAnalyticsWorker = async () => {
  log(`[AnalyticsWorker] Manual analytics worker started`);

  try {
    // Insert into platform_analytics
    log(`[AnalyticsWorker] Inserting platform analytics for today`);
    try {
      await client.query(
        `INSERT INTO platform_analytics (date) 
         VALUES (CURRENT_DATE)
         ON CONFLICT (date) DO NOTHING`
      );
      log(`[AnalyticsWorker] Platform analytics inserted`);
    } catch (dbErr) {
      logError(`[AnalyticsWorker] Failed to insert platform_analytics:`, dbErr);
    }

    // Insert into financial_analytics - triggers will populate the rest
    log(`[AnalyticsWorker] Inserting financial analytics for today`);
    try {
      await client.query(
        `INSERT INTO financial_analytics (date) 
         VALUES (CURRENT_DATE)
         ON CONFLICT (date) DO NOTHING`
      );
      log(`[AnalyticsWorker] Financial analytics inserted`);
    } catch (dbErr) {
      logError(`[AnalyticsWorker] Failed to insert financial_analytics:`, dbErr);
    }

  } catch (err) {
    logError(`[AnalyticsWorker] Error processing analytics:`, err);
  }

  log(`[AnalyticsWorker] Manual analytics worker finished`);
};
// -----------------------------
// --- WORKER FUNCTION ---
// -----------------------------
const startWorker = async () => {
  log(`[Worker] Worker initialized`);
  // Run immediately
  await runManualJobCloser();
  await runManualRefundWorker();
  // Analytics only runs on schedule, not on startup

  // --- Job Closer ---
  const scheduleJobCloser = () => {
    const now = new Date();
    const nextRun = new Date();
    nextRun.setHours(0, 1, 0, 0); // start 00:01
    if (now >= nextRun) nextRun.setDate(nextRun.getDate() + 1);
    const delay = nextRun.getTime() - now.getTime();
    log(`[JobCloser] Next run scheduled in ${Math.round(delay / 1000 / 60)} minutes`);
    setTimeout(() => {
      runManualJobCloser();
      setInterval(runManualJobCloser, JOB_CLOSER_TIMEFRAME_MS);
    }, delay);
  };

  // --- Refund Worker ---
  const scheduleRefundWorker = () => {
    const now = new Date();
    const nextRun = new Date();
    nextRun.setHours(0, 5, 0, 0); // start 00:05
    if (now >= nextRun) nextRun.setDate(nextRun.getDate() + 1);
    const delay = nextRun.getTime() - now.getTime();
    log(`[Worker] Refund worker next run in ${Math.round(delay / 1000 / 60)} minutes`);
    setTimeout(() => {
      runManualRefundWorker();
      setInterval(runManualRefundWorker, REFUND_WORKER_TIMEFRAME_MS);
    }, delay);
  };

  // --- Analytics Worker ---
  const scheduleAnalyticsWorker = () => {
    const now = new Date();
    const nextRun = new Date();
    nextRun.setHours(23, 59, 0, 0); // start 23:59
    if (now >= nextRun) nextRun.setDate(nextRun.getDate() + 1);
    const delay = nextRun.getTime() - now.getTime();
    log(`[AnalyticsWorker] Next run scheduled in ${Math.round(delay / 1000 / 60)} minutes`);
    setTimeout(() => {
      runManualAnalyticsWorker();
      setInterval(runManualAnalyticsWorker, ANALYTICS_WORKER_TIMEFRAME_MS);
    }, delay);
  };

  scheduleJobCloser();
  scheduleRefundWorker();
  scheduleAnalyticsWorker();

  return {
    runManualJobCloser,
    runManualRefundWorker,
    runManualAnalyticsWorker,
  };
};

// -----------------------------
// --- START SERVER ---
// -----------------------------
(async () => {
  try {
    await client.connect();
    const PORT = process.env.PORT || 3000;

    const { runManualJobCloser, runManualRefundWorker, runManualAnalyticsWorker } = await startWorker();

    app.listen(PORT, "0.0.0.0", () => {
      console.log(`API running on port ${PORT}`);
      console.log(`[Worker] Daily workers started`);
      console.log(`[Tasks]`);
      console.log(`   1 : Close ended jobs   [every ${JOB_CLOSER_TIMEFRAME_MS / (1000*60*60)} hrs, starting 00:01]`);
      console.log(`   2 : Issue refunds      [every ${REFUND_WORKER_TIMEFRAME_MS / (1000*60*60)} hrs, starting 00:05]`);
      console.log(`   3 : Collect analytics  [every ${ANALYTICS_WORKER_TIMEFRAME_MS / (1000*60*60)} hrs, starting 23:59]`);
      console.log(`[Logging]`, __wantLogs);
    });

    // Manual trigger endpoint
    app.post("/worker/run", async (_req, res) => {
      try {
        log(`[Worker] Manual trigger invoked`);
        await runManualRefundWorker();
        await runManualJobCloser();
        await runManualAnalyticsWorker();
        res.json({ status: "Worker run triggered manually (all tasks)" });
      } catch (err) {
        logError(`[Worker] Manual trigger error:`, err.message);
        res.status(500).json({ error: err.message });
      }
    });

  } catch (err) {
    console.error("Failed to connect to Postgres:", err);
    process.exit(1);
  }
})();