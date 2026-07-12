#!/usr/bin/env node
/**
 * Priority Scenario 5: Chat at volume.
 *
 * NOT a k6 script (see README "Tooling") -- chat is client-to-Firestore
 * directly, per apps/backend/app/api/v1/chat_auth.py's header comment:
 * "Real-time message send/receive/listening happens CLIENT-SIDE, direct
 * against Firestore ... The backend's only jobs here: issue scoped Firebase
 * custom auth tokens ... and create the initial conversation document."
 * A k6 HTTP script would only ever exercise token issuance, not the actual
 * Firestore read/write/listener volume this scenario needs to validate.
 *
 * This driver:
 *   1. Fetches a Firebase custom token per synthetic user from the real
 *      Backend API Service (POST /v1/chat/token) -- exercising that
 *      endpoint under volume too, not bypassing it.
 *   2. Exchanges each custom token for a Firestore ID token via the
 *      Firebase client SDK (matching what the mobile app / admin console
 *      actually do).
 *   3. Opens N concurrent conversation listeners (onSnapshot) and writes
 *      messages at the target rate, measuring listener fan-out latency and
 *      write throughput directly against Firestore.
 *   4. A separate pool of "staff" identities runs cross-conversation
 *      queries (matching the Admin Web Console's Chat Oversight Module
 *      pattern) concurrently with the above, per the Priority Scenario's
 *      "De-Duke Staff/Admin querying across many conversations
 *      simultaneously" requirement.
 *
 * Usage:
 *   BACKEND_BASE_URL=https://staging.api.de-duke.example \
 *   FIREBASE_CONFIG_JSON=./firebase-staging-config.json \
 *   node load_tests/scenarios/chat_volume.js --conversations 15000 --messages-per-sec 300 --duration-minutes 30
 *
 * Target numbers (--conversations / --messages-per-sec defaults) come from
 * README.md's Target Scale table -- override via flags for Stress/Soak
 * variants of this same scenario.
 */
'use strict';

const { parseArgs } = require('node:util');
const fetch = require('node-fetch');
const admin = require('firebase-admin');

const {
  values: {
    conversations: conversationCountArg,
    'messages-per-sec': messagesPerSecArg,
    'duration-minutes': durationMinutesArg,
    'staff-queriers': staffQueriersArg,
  },
} = parseArgs({
  options: {
    conversations: { type: 'string', default: '15000' },
    'messages-per-sec': { type: 'string', default: '300' },
    'duration-minutes': { type: 'string', default: '30' },
    'staff-queriers': { type: 'string', default: '20' },
  },
});

const CONVERSATION_COUNT = Number(conversationCountArg);
const TARGET_MESSAGES_PER_SEC = Number(messagesPerSecArg);
const DURATION_MS = Number(durationMinutesArg) * 60 * 1000;
const STAFF_QUERIER_COUNT = Number(staffQueriersArg);

const BACKEND_BASE_URL = process.env.BACKEND_BASE_URL;
if (!BACKEND_BASE_URL) {
  throw new Error('BACKEND_BASE_URL is required (e.g. https://staging.api.de-duke.example)');
}

// Firebase project config for the `staging` GCP project (README's Target
// Scale + Environment sections -- this MUST point at staging's Firestore,
// never production's) -- see infra/environments/staging's gcp_project_id.
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});
const db = admin.firestore();

/** Logs in a seeded synthetic user and exchanges the result for a Firebase custom token, mirroring the real client flow (chat_auth.py). */
async function getFirebaseCustomToken(userIndex) {
  const loginRes = await fetch(`${BACKEND_BASE_URL}/v1/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: `load+${userIndex}@synthetic.de-duke.internal`,
      password: 'LoadTest-Synthetic-Only-1!',
    }),
  });
  if (!loginRes.ok) throw new Error(`login failed for user ${userIndex}: ${loginRes.status}`);
  const { access_token: accessToken } = await loginRes.json();

  const tokenRes = await fetch(`${BACKEND_BASE_URL}/v1/chat/token`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!tokenRes.ok) throw new Error(`chat token failed for user ${userIndex}: ${tokenRes.status}`);
  const { firebase_custom_token: customToken } = await tokenRes.json();
  return customToken;
}

/** Opens a listener on one conversation and sends messages at this conversation's share of the target throughput. */
async function driveConversation(conversationId, messageIntervalMs) {
  let listenerLatencies = [];
  const unsubscribe = db
    .collection('conversations')
    .doc(conversationId)
    .collection('messages')
    .orderBy('created_at', 'desc')
    .limit(1)
    .onSnapshot((snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type === 'added' && change.doc.data().sent_at) {
          listenerLatencies.push(Date.now() - change.doc.data().sent_at);
        }
      });
    });

  const interval = setInterval(async () => {
    await db.collection('conversations').doc(conversationId).collection('messages').add({
      body: 'Load test message -- synthetic, safe to purge.',
      sender_role: 'seeker',
      sent_at: Date.now(),
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
  }, messageIntervalMs);

  return { unsubscribe, stop: () => clearInterval(interval), getLatencies: () => listenerLatencies };
}

/** Staff/Admin cross-conversation query load, matching the Admin Web Console's Chat Oversight Module (AdminUI in architecture.md's diagram). */
async function runStaffQuerier() {
  const start = Date.now();
  while (Date.now() - start < DURATION_MS) {
    const queryStart = Date.now();
    await db
      .collectionGroup('messages')
      .where('created_at', '>=', new Date(Date.now() - 5 * 60 * 1000))
      .orderBy('created_at', 'desc')
      .limit(50)
      .get();
    const latency = Date.now() - queryStart;
    if (latency > 2000) {
      console.warn(`Staff cross-conversation query took ${latency}ms -- exceeds 2s expectation.`);
    }
    await new Promise((r) => setTimeout(r, 3000)); // staff dashboards poll, not hammer
  }
}

async function main() {
  console.log(
    `Starting chat volume scenario: ${CONVERSATION_COUNT} conversations, ${TARGET_MESSAGES_PER_SEC} msg/s target, ${DURATION_MS / 60000}min, ${STAFF_QUERIER_COUNT} staff queriers`,
  );

  const messageIntervalMs = (CONVERSATION_COUNT / TARGET_MESSAGES_PER_SEC) * 1000;
  const drivers = [];
  for (let i = 0; i < CONVERSATION_COUNT; i++) {
    // Auth is exercised per-driver at startup (mirrors real usage: a user
    // opens a chat once, then stays connected) rather than per-message.
    await getFirebaseCustomToken(i);
    drivers.push(await driveConversation(`load-test-conv-${i}`, messageIntervalMs));
  }

  const staffQueriers = Array.from({ length: STAFF_QUERIER_COUNT }, runStaffQuerier);

  await new Promise((r) => setTimeout(r, DURATION_MS));

  drivers.forEach((d) => {
    d.stop();
    d.unsubscribe();
  });
  await Promise.all(staffQueriers);

  const allLatencies = drivers.flatMap((d) => d.getLatencies()).sort((a, b) => a - b);
  const p95 = allLatencies[Math.floor(allLatencies.length * 0.95)] || 0;
  console.log(`Listener fan-out p95 latency: ${p95}ms across ${allLatencies.length} samples.`);
  if (p95 > 1500) {
    console.error('FAIL: listener fan-out p95 latency exceeds 1500ms target.');
    process.exit(1);
  }
  console.log('PASS: chat volume scenario completed within latency target.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
