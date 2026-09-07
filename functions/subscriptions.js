/**
 * Subscription State Management Cloud Functions
 *
 * Handles automatic creation of subscription_state/current when store is approved
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/**
 * Auto-creates subscription_state/current when store status changes to "approved"
 */
exports.onStoreApproved = functions.firestore
  .document('stores/{storeId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const storeId = context.params.storeId;

    // Only trigger when status changes to "approved"
    if (before.status === 'approved' || after.status !== 'approved') {
      console.log(`⏭️  Skipping (status unchanged or not approved): ${storeId}`);
      return null;
    }

    console.log(`🚀 Store approved: ${storeId}. Creating subscription_state...`);

    try {
      // Check if subscription_state/current already exists
      const existingDoc = await db
        .collection('stores')
        .doc(storeId)
        .collection('subscription_state')
        .doc('current')
        .get();

      if (existingDoc.exists) {
        console.log(`⏭️  subscription_state/current already exists for ${storeId}`);
        return null;
      }

      // Get the default plan (Starter Monthly)
      const planDoc = await db
        .collection('platform_subscription_plans')
        .doc('monthly-starter')
        .get();

      if (!planDoc.exists) {
        console.error(`❌ Default plan 'monthly-starter' not found`);
        throw new Error('Default subscription plan not found');
      }

      const plan = planDoc.data();

      // Calculate trial end date (7 days from now)
      const now = new Date();
      const trialEnd = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);

      // Create the entitlement document
      const entitlementData = {
        status: 'trialing',
        planId: plan.id,
        planName: plan.name,
        billingCycle: plan.billingCycle,
        priceMinor: plan.priceMinor,
        currency: plan.currency,
        featureList: plan.featureList || [],
        limits: plan.limits || {},
        effectiveFrom: admin.firestore.FieldValue.serverTimestamp(),
        effectiveUntil: admin.firestore.Timestamp.fromDate(trialEnd),
        sourceSubscriptionId: 'welcome-trial',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Write subscription_state/current to Firestore
      await db
        .collection('stores')
        .doc(storeId)
        .collection('subscription_state')
        .doc('current')
        .set(entitlementData);

      console.log(`✅ Created subscription_state/current for ${storeId}`);
      console.log(`   Plan: ${plan.name}`);
      console.log(`   Trial ends: ${trialEnd.toISOString()}`);

      return {
        success: true,
        storeId: storeId,
        planId: plan.id,
        planName: plan.name,
      };
    } catch (error) {
      console.error(`❌ Error creating subscription_state for ${storeId}:`, error);
      return { error: error.message };
    }
  });

/**
 * Updates subscription_state/current when customer_subscriptions changes
 */
exports.projectSubscriptionState = functions.firestore
  .document('stores/{storeId}/customer_subscriptions/{subscriptionId}')
  .onWrite(async (change, context) => {
    const storeId = context.params.storeId;
    const subscriptionId = context.params.subscriptionId;

    try {
      // Get all active subscriptions for this store
      const activeSubsSnapshot = await db
        .collection('stores')
        .doc(storeId)
        .collection('customer_subscriptions')
        .where('status', 'in', ['active', 'trialing'])
        .orderBy('updatedAt', 'desc')
        .limit(1)
        .get();

      if (activeSubsSnapshot.empty) {
        console.log(`⏭️  No active subscriptions for ${storeId}`);
        return null;
      }

      const activeSub = activeSubsSnapshot.docs[0].data();
      const planId = activeSub.planId;

      // Get the plan details
      const planDoc = await db
        .collection('platform_subscription_plans')
        .doc(planId)
        .get();

      if (!planDoc.exists) {
        console.error(`Plan not found: ${planId}`);
        return null;
      }

      const plan = planDoc.data();

      // Project subscription state
      const entitlementData = {
        status: activeSub.status,
        planId: plan.id,
        planName: plan.name,
        billingCycle: plan.billingCycle,
        priceMinor: plan.priceMinor,
        currency: plan.currency,
        featureList: plan.featureList || [],
        limits: plan.limits || {},
        effectiveFrom: activeSub.startedAt || admin.firestore.FieldValue.serverTimestamp(),
        effectiveUntil: activeSub.currentPeriodEnd,
        sourceSubscriptionId: subscriptionId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db
        .collection('stores')
        .doc(storeId)
        .collection('subscription_state')
        .doc('current')
        .set(entitlementData);

      console.log(`✅ Projected subscription state for ${storeId}: ${plan.name}`);
      return { success: true };
    } catch (error) {
      console.error(`❌ Error projecting subscription state:`, error);
      return { error: error.message };
    }
  });

/**
 * Marks subscriptions as expired when currentPeriodEnd passes
 */
exports.expireSubscriptions = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    console.log('🔄 Running subscription expiry check...');

    try {
      const now = admin.firestore.Timestamp.now();

      // Find subscriptions that should be expired
      const expiredSubsSnapshot = await db
        .collectionGroup('customer_subscriptions')
        .where('status', 'in', ['active', 'trialing'])
        .where('currentPeriodEnd', '<', now)
        .get();

      if (expiredSubsSnapshot.empty) {
        console.log('ℹ️  No subscriptions to expire');
        return { processed: 0 };
      }

      // Mark as expired
      const batch = db.batch();
      let count = 0;

      expiredSubsSnapshot.forEach((doc) => {
        batch.update(doc.ref, {
          status: 'expired',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
      });

      await batch.commit();
      console.log(`✅ Marked ${count} subscription(s) as expired`);
      return { processed: count };
    } catch (error) {
      console.error(`❌ Error expiring subscriptions:`, error);
      throw error;
    }
  });
