const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const { Resend } = require("resend");

admin.initializeApp();

const db = admin.firestore();
const resendApiKey = defineSecret("RESEND_API_KEY");
// Commented out for now - enable when setting up Twilio SMS/WhatsApp
// const twilioAccountSid = defineSecret("TWILIO_ACCOUNT_SID");
// const twilioAuthToken = defineSecret("TWILIO_AUTH_TOKEN");

const INFO_EMAIL = "info@mypocketpos.in";

function parseChannelConfig(map, key) {
  if (!map || typeof map !== "object") {
    return { enabled: false, fromAddress: null, fromNumber: null };
  }
  const channel = map[key];
  if (!channel || typeof channel !== "object") {
    return { enabled: false, fromAddress: null, fromNumber: null };
  }

  const fromAddress =
    typeof channel.fromAddress === "string" && channel.fromAddress.trim().length > 0
      ? channel.fromAddress.trim()
      : null;
  const fromNumber =
    typeof channel.fromNumber === "string" && channel.fromNumber.trim().length > 0
      ? channel.fromNumber.trim()
      : null;
  const apiKey =
    typeof channel.apiKey === "string" && channel.apiKey.trim().length > 0
      ? channel.apiKey.trim()
      : null;
  const accountSid =
    typeof channel.accountSid === "string" && channel.accountSid.trim().length > 0
      ? channel.accountSid.trim()
      : null;
  const authToken =
    typeof channel.authToken === "string" && channel.authToken.trim().length > 0
      ? channel.authToken.trim()
      : null;

  return {
    enabled: channel.enabled === true,
    fromAddress,
    fromNumber,
    apiKey,
    accountSid,
    authToken,
  };
}

function readEmailFeatureFlags(map) {
  return parseChannelConfig(map, "email");
}

/* Twilio configuration reader commented out
function readSmsFeatureFlags(map) {
  return parseChannelConfig(map, "sms");
}

function readWhatsappFeatureFlags(map) {
  return parseChannelConfig(map, "whatsapp");
}
*/

function normalizePhone(value) {
  if (typeof value !== "string") return null;
  const raw = value.trim();
  if (!raw) return null;

  const cleaned = raw.replace(/[\s\-()]/g, "");
  if (/^\+[1-9]\d{7,14}$/.test(cleaned)) return cleaned;

  const digits = cleaned.replace(/\D/g, "");
  if (digits.length === 10) return `+91${digits}`;
  if (digits.length === 11 && digits.startsWith("0")) return `+91${digits.slice(1)}`;
  return null;
}

async function appendNotificationLog(entry) {
  await db.collection("notification_logs").add({
    ...entry,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
}

/* Twilio API integration commented out
async function sendViaTwilio({ from, to, body, accountSid, authToken }) {
  const endpoint =
    `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const auth = Buffer.from(`${accountSid}:${authToken}`).toString("base64");

  const params = new URLSearchParams();
  params.set("From", from);
  params.set("To", to);
  params.set("Body", body);

  const resp = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Twilio send failed (${resp.status}): ${text}`);
  }
}
*/

function readSecretValue(secretParam) {
  try {
    const value = secretParam.value();
    return typeof value === "string" && value.trim().length > 0
      ? value.trim()
      : null;
  } catch (_) {
    return null;
  }
}

exports.sendWelcomeEmailOnStoreRegistration = onDocumentCreated(
  {
    document: "stores/{storeId}",
    region: "asia-south1",
    secrets: [resendApiKey /*, twilioAccountSid, twilioAuthToken */],
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const storeSnap = event.data;
    if (!storeSnap) {
      logger.warn("Store create event had no snapshot data.");
      return;
    }

    const storeId = event.params.storeId;
    const store = storeSnap.data() || {};
    const ownerEmail = typeof store.email === "string" ? store.email.trim() : "";

    let config;
    try {
      const cfgSnap = await db.collection("platform_config").doc("notifications").get();
      config = cfgSnap.data();
    } catch (err) {
      // Fail-safe: config read issues must not break registration flow.
      logger.error("Failed to read notification config; treating as disabled.", {
        storeId,
        error: String(err),
      });
      return;
    }

    const emailCfg = readEmailFeatureFlags(config);
    const defaultResendApiKey = readSecretValue(resendApiKey);

    const storeName =
      typeof store.name === "string" && store.name.trim().length > 0
        ? store.name.trim()
        : storeId;
    const ownerName =
      typeof store.ownerName === "string" && store.ownerName.trim().length > 0
        ? store.ownerName.trim()
        : "Store Owner";
    const ownerUsername =
      typeof store.ownerUsername === "string" && store.ownerUsername.trim().length > 0
        ? store.ownerUsername.trim()
        : "";

    const fromAddress =
      emailCfg.fromAddress || "Pocket POS <onboarding@updates.mypocketpos.in>";

    const emailSubject = `Welcome to Pocket POS - ${storeId}`;
    const plainBody = [
      `Hi ${ownerName},`,
      "",
      `Welcome to Pocket POS for \"${storeName}\".`,
      `Your Store ID is: ${storeId}`,
      "",
      "Your store is currently pending platform approval.",
      "Once approved, you can log in and start billing.",
      "",
      "Regards,",
      "Pocket POS Team",
    ].join("\n");

    const htmlBody = `
      <div style="font-family: Arial, sans-serif; line-height: 1.5; color: #222;">
        <p>Hi ${ownerName},</p>
        <p>Welcome to Pocket POS for <strong>${storeName}</strong>.</p>
        <p>Your Store ID is: <strong>${storeId}</strong></p>
        <p>Your Store Username is: <strong>${ownerUsername}</strong></p>
        <p>Your store is currently pending platform approval.<br/>Once approved, you can log in and start billing.</p>
        <p>Regards,<br/>Pocket POS Team</p>
      </div>
    `;

    const tasks = [];

    if (emailCfg.enabled) {
      if (!ownerEmail) {
        tasks.push(
          appendNotificationLog({
            channel: "email",
            template: "welcome_registration",
            storeId,
            status: "skipped",
            reason: "missing_owner_email",
          })
        );
      } else {
        tasks.push((async () => {
          try {
            const effectiveEmailApiKey = emailCfg.apiKey || defaultResendApiKey;
            if (!effectiveEmailApiKey) {
              throw new Error("Missing Resend API key for email channel.");
            }
            const resend = new Resend(effectiveEmailApiKey);
            await resend.emails.send({
              from: fromAddress,
              to: [ownerEmail],
              cc: [INFO_EMAIL],
              subject: emailSubject,
              text: plainBody,
              html: htmlBody,
            });

            await appendNotificationLog({
              channel: "email",
              template: "welcome_registration",
              storeId,
              to: ownerEmail,
              cc: [INFO_EMAIL],
              status: "sent",
            });
          } catch (err) {
            logger.error("Welcome email send failed.", {
              storeId,
              to: ownerEmail,
              error: String(err),
            });

            await appendNotificationLog({
              channel: "email",
              template: "welcome_registration",
              storeId,
              to: ownerEmail,
              cc: [INFO_EMAIL],
              status: "failed",
              error: String(err),
            });
          }
        })());
      }
    } else {
      tasks.push(
        appendNotificationLog({
          channel: "email",
          template: "welcome_registration",
          storeId,
          status: "skipped",
          reason: "feature_disabled",
        })
      );
    }

    /* SMS Block Commented Out
    if (smsCfg.enabled) { ... }
    */

    /* WhatsApp Block Commented Out
    if (whatsappCfg.enabled) { ... }
    */

    // Fail-safe: notification pipeline is best effort. Never throw from trigger.
    await Promise.allSettled(tasks);
  }
);

function readTimestamp(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function toWireStatus(status) {
  if (status === "pastDue") return "past_due";
  return status;
}

function deriveSubscriptionStatus(rawStatus, now, periodEnd, trialEnd) {
  const status = typeof rawStatus === "string" && rawStatus.trim().length > 0
    ? rawStatus.trim()
    : "pending";

  const effectiveEnd = periodEnd || trialEnd;
  if (status === "trialing" && effectiveEnd && effectiveEnd < now) {
    return "expired";
  }
  if (status === "active" && effectiveEnd && effectiveEnd < now) {
    return "past_due";
  }
  return status;
}

async function projectStoreSubscriptionState(storeId) {
  const now = new Date();
  const subsSnap = await db
    .collection("stores")
    .doc(storeId)
    .collection("customer_subscriptions")
    .orderBy("updatedAt", "desc")
    .limit(40)
    .get();

  const preferredStatuses = ["trialing", "active", "past_due", "pending", "canceled", "expired"];
  let chosen = null;
  for (const status of preferredStatuses) {
    chosen = subsSnap.docs.find((doc) => {
      const data = doc.data() || {};
      return (data.status || "pending") === status;
    });
    if (chosen) break;
  }

  const entitlementRef = db
    .collection("stores")
    .doc(storeId)
    .collection("subscription_state")
    .doc("current");

  if (!chosen) {
    await entitlementRef.set(
      {
        status: "pending",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await db.collection("stores").doc(storeId).set(
      {
        subscriptionStatus: "pending",
        subscriptionPlanId: admin.firestore.FieldValue.delete(),
        subscriptionCurrentPeriodEnd: admin.firestore.FieldValue.delete(),
        subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return;
  }

  const chosenData = chosen.data() || {};
  const planId = chosenData.planId;
  if (typeof planId !== "string" || planId.trim().length === 0) {
    return;
  }

  const planDoc = await db.collection("platform_subscription_plans").doc(planId).get();
  if (!planDoc.exists) {
    await entitlementRef.set(
      {
        status: "pending",
        planId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return;
  }

  const plan = planDoc.data() || {};
  const periodEnd = readTimestamp(chosenData.currentPeriodEnd);
  const trialEnd = readTimestamp(chosenData.trialEndAt);
  const computedStatus = deriveSubscriptionStatus(
    chosenData.status,
    now,
    periodEnd,
    trialEnd
  );

  await chosen.ref.set(
    {
      status: computedStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await entitlementRef.set(
    {
      status: computedStatus,
      planId,
      planName: plan.name || plan.slug || "",
      billingCycle: plan.billingCycle || "monthly",
      priceMinor: Number.isFinite(plan.priceMinor) ? plan.priceMinor : 0,
      currency: typeof plan.currency === "string" ? plan.currency : "INR",
      featureList: Array.isArray(plan.featureList) ? plan.featureList : [],
      limits: typeof plan.limits === "object" && plan.limits !== null ? plan.limits : {},
      effectiveFrom: chosenData.currentPeriodStart || chosenData.startedAt || null,
      effectiveUntil: chosenData.currentPeriodEnd || chosenData.trialEndAt || null,
      sourceSubscriptionId: chosen.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  await db.collection("stores").doc(storeId).set(
    {
      subscriptionStatus: computedStatus,
      subscriptionPlanId: planId,
      subscriptionCurrentPeriodEnd: chosenData.currentPeriodEnd || chosenData.trialEndAt || null,
      subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

exports.syncStoreSubscriptionProjection = onDocumentWritten(
  {
    document: "stores/{storeId}/customer_subscriptions/{subscriptionId}",
    region: "asia-south1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const storeId = event.params.storeId;
    try {
      await projectStoreSubscriptionState(storeId);
    } catch (error) {
      logger.error("Subscription projection sync failed", {
        storeId,
        error: String(error),
      });
    }
  }
);

exports.bootstrapStoreTrialSubscription = onDocumentCreated(
  {
    document: "stores/{storeId}",
    region: "asia-south1",
    timeoutSeconds: 30,
    memory: "256MiB",
  },
  async (event) => {
    const storeId = event.params.storeId;
    try {
      const storeData = event.data?.data() || {};
      const ownerUid = storeData.ownerUid;

      const plansSnap = await db
        .collection("platform_subscription_plans")
        .where("defaultForNewStores", "==", true)
        .where("isActive", "==", true)
        .where("deletedAt", "==", null)
        .orderBy("sortOrder")
        .limit(1)
        .get();

      if (plansSnap.empty) return;
      const planDoc = plansSnap.docs[0];
      const plan = planDoc.data() || {};
      const trialDays = Number.isFinite(plan.trialDays) ? plan.trialDays : 0;
      const safeTrialDays = trialDays > 0 ? trialDays : 14;

      const now = admin.firestore.Timestamp.now();
      const end = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + safeTrialDays * 24 * 60 * 60 * 1000)
      );

      await db
        .collection("stores")
        .doc(storeId)
        .collection("customer_subscriptions")
        .doc("bootstrap_trial")
        .set(
          {
            storeId,
            planId: planDoc.id,
            status: "trialing",
            source: "backend",
            provider: "none",
            cancelAtPeriodEnd: false,
            startedAt: now,
            trialEndAt: end,
            currentPeriodStart: now,
            currentPeriodEnd: end,
            metadata: {
              seeded: true,
              assignedBy: "bootstrapStoreTrialSubscription",
              ownerUid: typeof ownerUid === "string" ? ownerUid : null,
            },
            createdAt: now,
            updatedAt: now,
          },
          { merge: true }
        );

      await projectStoreSubscriptionState(storeId);
    } catch (error) {
      logger.error("Store trial bootstrap failed", {
        storeId,
        error: String(error),
      });
    }
  }
);
// Load subscription management functions
require('./subscriptions');
