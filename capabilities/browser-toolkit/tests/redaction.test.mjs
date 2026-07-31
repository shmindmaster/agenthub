import assert from "node:assert/strict";
import { redactSensitiveText } from "../scripts/redact-sensitive-text.mjs";

const secrets = ["abc.def.ghi", "key value with spaces", "session=private-value"];
const input = [
  "authorization: Bearer abc.def.ghi",
  "x-api-key: \"key value with spaces\"",
  "Cookie: session=private-value; theme=dark"
].join("\n");
const output = redactSensitiveText(input);

for (const secret of secrets) assert.equal(output.includes(secret), false, `redactor leaked ${secret}`);
assert.match(output, /authorization: <redacted>/i);
assert.match(output, /x-api-key: <redacted>/i);
assert.match(output, /Cookie: <redacted>/i);
console.log("Sensitive browser-evidence redaction tests passed.");
