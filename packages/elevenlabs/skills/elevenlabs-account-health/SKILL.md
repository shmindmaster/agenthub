---
name: elevenlabs-account-health
description: Use when ElevenLabs authentication, account availability, or safe quota metadata must be checked without generating media.
---

# ElevenLabs Account Health

Run `scripts/elevenlabs_cli.py health` to call `/v1/user`. The output reports
only success and non-sensitive subscription metadata. Run `voices` to count and
list voice IDs/names when needed; do not expose unrelated account data.
