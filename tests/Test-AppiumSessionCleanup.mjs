import assert from "node:assert/strict";
import { cleanupCreatedSessions } from "../packages/mobile-development/skills/mobile-device-lab/scripts/AppiumSessionCleanup.mjs";

const successIds = ["android-session", "ios-session"];
const deletionOrder = [];
const successErrors = await cleanupCreatedSessions(successIds, async (sessionId) => {
  deletionOrder.push(sessionId);
});
assert.deepEqual(deletionOrder, ["ios-session", "android-session"]);
assert.deepEqual(successErrors, []);
assert.deepEqual(successIds, []);
console.log("PASS: executable cleanup deletes every created session in reverse order and clears ownership state");

const failureIds = ["android-session", "ios-session"];
const attempted = [];
const failureErrors = await cleanupCreatedSessions(failureIds, async (sessionId) => {
  attempted.push(sessionId);
  if (sessionId === "ios-session") throw new Error("synthetic delete failure");
});
assert.deepEqual(attempted, ["ios-session", "android-session"]);
assert.equal(failureErrors.length, 1);
assert.match(failureErrors[0], /ios-session: synthetic delete failure/);
assert.deepEqual(failureIds, []);
console.log("PASS: executable cleanup records a deletion failure and still attempts remaining sessions");
console.log("RESULT: 2 passed, 0 failed");
