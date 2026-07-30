---
name: voiceover
description: Adding AI-generated voiceover to Remotion compositions using TTS
metadata:
  tags: voiceover, audio, elevenlabs, tts, speech, calculateMetadata, dynamic duration
---

# Adding AI voiceover to a Remotion composition

Use ElevenLabs TTS to generate speech audio per scene, then use [`calculateMetadata`](./calculate-metadata) to dynamically size the composition to match the audio.

## Prerequisites

Product Demo Studio is provider-agnostic. Use the provider and voice profile approved for the
target repo, verify the current model/voice/deprecation state before a billed run, and resolve its
credential from an environment-variable reference. Never ask the user to paste an API key and
never switch providers merely because another key happens to be present.

Ensure the environment variable is available when running the generation script:

```bash
node --strip-types generate-voiceover.ts
```

## Generating audio with ElevenLabs

`use-elevenlabs` is the single provider owner. Do not add another ElevenLabs HTTP client to a
product video workspace. Product Demo Studio's `generate-narration.mjs` delegates to the
AgentHub-managed CLI, which preserves the approved voice/model settings and writes each
checksumable audio artifact:

```bash
python "<AGENTHUB_ROOT>/packages/portfolio-plugins/use-elevenlabs/scripts/elevenlabs_cli.py" \
  tts \
  --text "Welcome to the show." \
  --output "public/voiceover/<composition-id>/<scene-id>.mp3" \
  --voice-id "<approved-voice-id>" \
  --model-id "<approved-model-id>" \
  --stability 0.5 \
  --similarity-boost 0.75 \
  --style 0.3
```

Record the capability version, model, voice ID, settings, input text hash, output hash, and
generation command in the narration manifest. Never copy credentials into a script, manifest, or
adapter.

## Dynamic composition duration with calculateMetadata

Use [`calculateMetadata`](./calculate-metadata.md) to measure the [audio durations](./get-audio-duration.md) and set the composition length accordingly.

```tsx
import { CalculateMetadataFunction, staticFile } from "remotion";
import { getAudioDuration } from "./get-audio-duration";

const FPS = 30;

const SCENE_AUDIO_FILES = [
  "voiceover/my-comp/scene-01-intro.mp3",
  "voiceover/my-comp/scene-02-main.mp3",
  "voiceover/my-comp/scene-03-outro.mp3",
];

export const calculateMetadata: CalculateMetadataFunction<Props> = async ({
  props,
}) => {
  const durations = await Promise.all(
    SCENE_AUDIO_FILES.map((file) => getAudioDuration(staticFile(file))),
  );

  const sceneDurations = durations.map((durationInSeconds) => {
    return durationInSeconds * FPS;
  });

  return {
    durationInFrames: Math.ceil(sceneDurations.reduce((sum, d) => sum + d, 0)),
  };
};
```

The computed `sceneDurations` are passed into the component via a `voiceover` prop so the component knows how long each scene should be.

If the composition uses [`<TransitionSeries>`](./transitions.md), subtract the overlap from total duration: [./transitions.md#calculating-total-composition-duration](./transitions.md#calculating-total-composition-duration)

## Rendering audio in the component

See [audio.md](./audio.md) for more information on how to render audio in the component.

## Delaying audio start

See [audio.md#delaying](./audio.md#delaying) for more information on how to delay the audio start.
