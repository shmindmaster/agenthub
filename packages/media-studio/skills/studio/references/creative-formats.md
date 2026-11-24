# Creative freedom and representation: film modes

Use the brief to select form, story, image language and pace. A complete delegated brief can proceed through internal creative review and production. Reserve separate approval for spending outside existing authority and external publication.

Media Studio is a **general-purpose filmmaker**. It is not a product-tour
generator or an ABACare-specific advertising system. Infer the desired format
from the request, not from the product's industry or a prior client film.
Photoreal people, families, children, patients, clinicians, stylized characters,
unblurred synthetic interfaces, fictional workflows, futuristic technology,
music, animation, 3D, generated video and entirely invented worlds are valid
creative materials. A completed fictional scene does not have to resemble
an existing software product. Do not inject arbitrary blur, "no text", "no
faces", "adults only", artificial logos or five-second cuts into the prompt.

## Two independent axes

**Creative form:** demo, explainer, documentary, short ad, tutorial, brand film,
day-in-the-life, fictional story, training, mini-drama, animation, abstract
film, technical story, future vision, or a hybrid. Do not force the
software-demo six-beat formula on other forms.

**Truth/representation:** each claim and depiction can be:
- **Verified:** the current product, real process, or factual external claim
  supported by appropriate source evidence; live-product behavior is shown
  by real, receipt-bound capture.
- **Proposed:** future feature, product concept, envisaged customer journey,
  speculative UI or "art of the possible".
- **Fictional:** invented character, patient/family/worker, dialogue, location,
  simulated outcome or dramatic situation.
- **Illustrative:** a synthetic shot that explains or symbolizes an idea,
  without claiming the actual screen/customer/event occurred.

Proposed and fictional do **not** mean prohibited, lower-quality, blurry,
watermarked on every shot or restricted to adult characters. Represent them
beautifully, coherently and legibly. The role of provenance is to prevent
a presentation from confusing *what exists now* with *what could exist*.

## Marketing ad JSON creativeMode

The `mvg` marketing spec accepts `creativeMode`:
- `verified-demo`: default to preserve older ads. Film demonstrates
  current features with genuine capture. It may also contain labeled `fictional` or `illustrative`
  surrounding scenes.
- `hybrid`: mixes sourced current-product footage with proposed/fictional
  visualizations. Mark any generated UI in `broll` using
  `depictsProductUI: true` and `truthStatus: proposed|fictional|illustrative`.
- `future-vision`: art of the possible, futuristic or imagined workflows.
  Fully generated human scenes and UI are legitimate; disclose clearly
  that the capabilities are envisioned, not shipped.
- `concept-film`: speculative designed interfaces, prototypes and
  product/brand concepts. The film can be entirely synthetic.
- `fictional-story`: mini drama, role-based day-in-the-life, human story,
  documentary-style fiction, kids/family/patient scenarios. No obligatory
  software recording or forced six-beat plot.
- `explainer`: a conceptual explanation with real or synthetic graphics.
- `documentary`: a documentary treatment chosen for the subject, such as observation, interviews, archive, narration or dramatized reconstruction. Identify a reconstruction where its status matters to the viewer.
- `educational`: training, instruction, practical or technical education.
- `abstract`: experimental film, non-linear sequences, visual poetry,
  purely conceptual animation.

The marketing generator remains a *marketing* workflow, so it still
requires its ad/CTA and supported media inputs. General narrative films,
training or documentaries can use the broader studio/video skill's
development, composition and review lanes. The JSON mode does not
magically enable video generation providers not already implemented
by `mvg`.

### Representation examples

**Verified feature walkthrough:** a genuine captured screen shows the user
submitting an action and observing the actual result. A generated shot can
portray a fictional worker seeing the before-state. Do not claim that
generated proposed interfaces are current released functionality.

**Envisioned future of care:** photorealistic fictional patients, children,
families, doctors and a rich, clear future health dashboard are legitimate
creative scenes, with no automatic blur, privacy masks or age exclusions.
Label the work once as a concept/future vision (e.g. opening title or end
card). The label concerns the *status of the technology*, not whether
synthetic people may be depicted.

**Day-in-the-life of a warehouse owner:** realistic worker scenes and a
speculative logistics UI can be entirely generated. The problem, effort,
solution and emotional progression are authored freely; no current-product
capture is required.

**Concept documentary:** dramatized reconstructions can intercut with
sourced facts. Annotate the boundary when necessary, but do not force a
traditional advertising CTA into a non-marketing documentary.

**Abstract brand film:** a recognizable story, emotion, metaphor, rhythmic
montage or music-led arc may replace literal character/obstacle/solution
beats; assess it against *its own intended experience*.

## Story and picture quality

Brief → treatment → beat map → script → shot plan → approved assets →
assembly → exact-candidate review. For fiction/vision, check emotional
truth and narrative coherence, character continuity, invented-world rules,
visual impact, pacing, scene transitions, typography and soundtrack.
For a verified product film, also check actual claim evidence, UI actions,
result timing and current-feature truth. For hybrid, check both.

Hooks, pattern interrupts, the midpoint reversal and CTAs are **tools**,
not universal structural requirements. A cold open, a chronological setup,
an expressive long take or a quiet reflective scene can be appropriate.
Choose the structure that serves the audience and goal.

## Practical consent, privacy and identity boundaries

Use legally obtained media and licensed likenesses where applicable.
Never represent invented testimony as a genuine real-person endorsement.
Real customer/patient data should only enter an approved workflow with
the required permissions and contracts. Synthetic actors and data do
not need real-data redaction. A generated clinical record, interface
or patient scene is permitted as a concept visualization but is not
evidence that a deployed service performs that function.

Keep source-hashed evidence for *verified* assertions and distinguish
those from proposed/fictional scenes. A film-level concept indication
may be enough; do not impose persistent corner watermarks, blur, or
synthetic-data speeches without a genuine use-case need.

## Generation and production limitations

The current `mvg` assets stage supports already implemented
`openai-image` b-roll, accepted licensed stock, and its historical
provider pathways. It does **not** automatically support new
Runware/ElevenLabs models or editable GIF/SVG/3D pipelines merely
because their public API schemas exist. For any new model, use the
provider cost-quality research document, quote supported inputs and
prices, add a governed adapter, check receipts and review output
before claiming the route is production-ready. Realistic unblurred
generated images can be authored by an eligible image model; generated
video requires a real video integration or accepted external source.
