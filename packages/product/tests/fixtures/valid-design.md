# Keep input after a failed send

## Outcome

A member can correct a failed invite without retyping it.

## Smallest slice

The invite form only.

## Target flow

Open, type, send, see the error, correct, send, see confirmation.

## States

Normal, error and success are defined.

## Keyboard

Focus moves to the error and returns to the Invite button on success.

## Acceptance tests

With an invalid email, pressing Send shows the error and keeps the typed value.

## Outcome metric

Invites sent without a retry; baseline 80%; threshold 90%.
