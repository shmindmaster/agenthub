---
name: elevenlabs-account-health
description: Verify ElevenLabs authentication and inspect safe account metadata without consuming media quota.
---

# ElevenLabs Account Health

Run `scripts/elevenlabs_cli.py health` to call `/v1/user`. The output reports
only success and non-sensitive subscription metadata. Run `voices` to count and
list voice IDs/names when needed; do not expose unrelated account data.
