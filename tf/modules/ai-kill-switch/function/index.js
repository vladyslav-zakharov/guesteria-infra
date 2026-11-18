'use strict';

const functions = require('@google-cloud/functions-framework');
const { GoogleAuth } = require('google-auth-library');

// Injected via service_config.environment_variables in main.tf.
const PROJECT_ID = process.env.PROJECT_ID;
const TARGET_SERVICES = (process.env.TARGET_SERVICES || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const BUDGET_DISPLAY_NAME = process.env.BUDGET_DISPLAY_NAME;

const auth = new GoogleAuth({ scopes: ['https://www.googleapis.com/auth/cloud-platform'] });

async function getServiceState(client, service) {
  const url = `https://serviceusage.googleapis.com/v1/projects/${PROJECT_ID}/services/${service}`;
  const res = await client.request({ url });
  return res.data.state; // 'ENABLED' | 'DISABLED' | 'STATE_UNSPECIFIED'
}

async function disableService(client, service) {
  const url = `https://serviceusage.googleapis.com/v1/projects/${PROJECT_ID}/services/${service}:disable`;
  // disableDependentServices: false is deliberate — if disabling this service
  // is blocked by a dependent service, we want that failure to surface loudly
  // rather than have the API cascade-disable things we didn't ask for.
  return client.request({
    url,
    method: 'POST',
    data: { disableDependentServices: false },
  });
}

/**
 * Eventarc Pub/Sub entry point, fired on every update to the ai-kill-switch
 * budget (google_billing_budget.kill_switch's all_updates_rule).
 *
 * IMPORTANT: Cloud Billing publishes a notification on every budget
 * recalculation — many times a day — not only when the threshold is crossed.
 * The payload schema (costAmount, budgetAmount, budgetDisplayName, etc.) is
 * documented at:
 *   https://cloud.google.com/billing/docs/how-to/budget-notifications-format
 * We therefore compare costAmount/budgetAmount ourselves on every invocation
 * instead of assuming "we got a notification" means "act now".
 */
const handleBudgetNotification = async (cloudEvent) => {
  const messageData = cloudEvent && cloudEvent.data && cloudEvent.data.message && cloudEvent.data.message.data;
  if (!messageData) {
    console.error(
      'No Pub/Sub message data on the CloudEvent — the kill-switch could not read the notification and is therefore not protecting anything.'
    );
    return;
  }

  let payload;
  try {
    payload = JSON.parse(Buffer.from(messageData, 'base64').toString('utf8'));
  } catch (err) {
    console.error('Failed to parse budget notification payload as JSON.', err);
    return;
  }

  console.log('Budget notification received.', JSON.stringify(payload));

  // Guard on display name so only THIS kill-switch budget's notifications can
  // ever trigger a disable — the project's existing alert budget (budget
  // module) is a separate google_billing_budget and must never reach this code.
  if (payload.budgetDisplayName !== BUDGET_DISPLAY_NAME) {
    console.log(
      `Notification is for budget "${payload.budgetDisplayName}", not the kill-switch budget "${BUDGET_DISPLAY_NAME}" — skipping.`
    );
    return;
  }

  const costAmount = Number(payload.costAmount);
  const budgetAmount = Number(payload.budgetAmount);

  if (!Number.isFinite(costAmount) || !Number.isFinite(budgetAmount) || budgetAmount <= 0) {
    console.log('Missing or invalid costAmount/budgetAmount on payload — skipping.', payload);
    return;
  }

  const ratio = costAmount / budgetAmount;
  console.log(`Spend ${costAmount} / budget ${budgetAmount} = ratio ${ratio.toFixed(3)} (threshold 1.0).`);

  if (ratio < 1.0) {
    console.log('Threshold not crossed yet — no action taken.');
    return;
  }

  console.log(`Threshold crossed (ratio ${ratio.toFixed(3)} >= 1.0) — disabling: ${TARGET_SERVICES.join(', ')}`);

  const client = await auth.getClient();

  for (const service of TARGET_SERVICES) {
    try {
      const state = await getServiceState(client, service);

      // Idempotent: a notification storm (many messages per day) must not
      // crash-loop or re-disable an already-disabled service.
      if (state === 'DISABLED') {
        console.log(`${service} is already DISABLED — no-op.`);
        continue;
      }

      await disableService(client, service);
      console.log(`Disabled ${service}.`);
    } catch (err) {
      const details = (err && err.response && err.response.data) || err;
      // Do NOT retry with disableDependentServices: true, and do not disable
      // any other service as a result of this failure — an unbounded
      // dependent-disable could take down far more than intended. Just log
      // loudly so it shows up in Cloud Logging and move on to the next service.
      console.error(`FAILED to disable ${service} — left enabled. Needs manual attention.`, details);
    }
  }
};

// The Functions Framework defaults to the HTTP signature. A plain
// `exports.handleBudgetNotification = ...` is therefore invoked as an HTTP
// handler, the CloudEvent never arrives, and the "cloudEvent" parameter is
// actually the Express req object — observed live as a 200 response plus the
// "no message data" branch above firing on every real notification. Must be
// registered explicitly as a CloudEvent function to receive the Pub/Sub payload.
functions.cloudEvent('handleBudgetNotification', handleBudgetNotification);
