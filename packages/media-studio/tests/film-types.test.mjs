// The story gate across products and film types, the recorded waiver, the
// product profile, and the routes a spec could once use to leave the truth rules.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { checkStory } from '../scripts/check-story.mjs';
import { lintSpec, CLAIM_POLICIES, DEFAULT_BANNED } from '../kit/marketing/lib/lint.mjs';
import { validate } from '../kit/marketing/lib/schema.mjs';
import { FILM_TYPES, rolesOf } from '../kit/marketing/lib/story-profiles.mjs';
import { beatIsFactual, inspectRepresentation } from '../kit/marketing/lib/creative-modes.mjs';
import { withProductProfile, productProfile } from '../kit/marketing/lib/product-profile.mjs';
import { evaluate } from '../kit/marketing/vision-qa.mjs';

const adSchema = JSON.parse(readFileSync(new URL('../kit/marketing/ad.schema.json', import.meta.url), 'utf8'));
const brandSchema = JSON.parse(readFileSync(new URL('../kit/marketing/brand.schema.json', import.meta.url), 'utf8'));
const rules = (report) => report.cuts.flatMap((c) => c.failures.map((f) => f.rule));

// ---- two products, two film types ------------------------------------------------------------------------

const rexaTutorial = () => ({
  product: 'Rexa', filmType: 'tutorial', targetSeconds: 90,
  narrative: { goal: 'Finish a first study session and see what comes back tomorrow' },
  beats: [
    { role: 'goal', line: 'In two minutes you will finish a first session and know what returns tomorrow.' },
    { role: 'step', line: 'Open the deck and press play. Rexa reads the first card aloud.' },
    { role: 'step', line: 'Say the answer before the voice does, then mark whether you had it.' },
    { role: 'payoff', line: 'The progress screen now lists the cards due tomorrow.' },
  ],
});

const revolvaMarketing = () => ({
  product: 'Revolva', filmType: 'product-marketing', targetSeconds: 45,
  cta: { text: 'See a delivery exception closed' },
  narrative: {
    persona: 'a delivery operations lead', situation: 'the morning after a missed mobility handoff',
    trigger: 'a source revision arrives overnight', problem: 'nobody knows which commitments the revision breaks',
    stakes: 'a client finds the gap before the team does', solution: 'Revolva shows what the revision changed',
    mechanism: 'the lead opens the revision and reads the affected commitments', payoff: 'the gap is assigned before stand-up',
    emotionalBefore: 'uneasy about what changed overnight', emotionalAfter: 'certain which commitment needs an owner',
    viewerValue: 'find the commitments a change breaks before a client does',
  },
  hookPlan: {
    visual: 'A revision notice on a delivery plan', onScreen: 'One revision. Which commitments broke?',
    spoken: 'A revision landed overnight.', viewerQuestion: 'Which commitments did it break?',
  },
  beats: [
    { role: 'hook', line: 'A revision landed overnight. Something you promised just changed.' },
    { role: 'context-problem', line: 'An operations lead opens the plan and cannot tell which commitments it touches.' },
    { role: 'solution', line: 'Revolva lines the revision up against every commitment.' },
    { role: 'demonstration', line: 'She opens the revision and reads the three commitments it affects.' },
    { role: 'payoff', line: 'The broken commitment has an owner before stand-up.' },
    { role: 'cta', line: 'See a delivery exception closed.' },
  ],
});

test('a good brief passes for two different products and two different film types', () => {
  const tutorial = checkStory(rexaTutorial());
  assert.equal(tutorial.ok, true, JSON.stringify(tutorial.cuts[0].failures));
  assert.equal(tutorial.cuts[0].filmType, 'tutorial');
  const marketing = checkStory(revolvaMarketing());
  assert.equal(marketing.ok, true, JSON.stringify(marketing.cuts[0].failures));
  assert.equal(marketing.cuts[0].filmType, 'product-marketing');
});

test('a context-free brief fails with messages that say what is missing', () => {
  const montage = revolvaMarketing();
  delete montage.narrative; delete montage.hookPlan;
  montage.beats = [
    { role: 'demonstration', line: 'The dashboard.' },
    { role: 'demonstration', line: 'The settings panel.' },
    { role: 'demonstration', line: 'Another tab.' },
  ];
  const report = checkStory(montage);
  assert.equal(report.ok, false);
  for (const rule of ['story.narrative', 'story.hook-plan', 'story.hook-first', 'story.context', 'story.problem', 'story.solution', 'story.payoff', 'story.cta-last']) {
    assert.ok(rules(report).includes(rule), `expected ${rule} in ${rules(report).join(', ')}`);
  }
  assert.match(report.cuts[0].failures.find((f) => f.rule === 'story.context').message, /who\/where/);

  const bareTutorial = rexaTutorial();
  delete bareTutorial.narrative;
  bareTutorial.beats = [{ role: 'step', line: 'Press play.' }];
  const tutorial = checkStory(bareTutorial);
  assert.equal(tutorial.ok, false);
  assert.ok(rules(tutorial).includes('story.narrative'));
  assert.ok(rules(tutorial).includes('story.goal'));
  assert.ok(rules(tutorial).includes('story.payoff'));
});

test('a film is judged by its own form, not by the marketing mould', () => {
  // A tutorial needs no hook plan, no emotional arc and no call to action.
  assert.equal(rules(checkStory(rexaTutorial())).some((r) => /cta|hook-plan|emotional/.test(r)), false);
  // The same beats declared as product marketing are missing most of a marketing film.
  const asMarketing = { ...rexaTutorial(), filmType: 'product-marketing' };
  assert.ok(rules(checkStory(asMarketing)).includes('story.cta-last'));
  // An explainer may show no product interface at all.
  const explainer = checkStory({
    product: 'CoLedger', filmType: 'explainer', creativeMode: 'explainer', targetSeconds: 60,
    narrative: { question: 'Why do two ledgers disagree at month end?', viewerValue: 'know the three causes of a ledger mismatch' },
    beats: [
      { role: 'hook', line: 'Two ledgers, one month, two different totals.' },
      { role: 'explanation', line: 'Timing, classification and currency each move a total without anyone making an error.' },
      { role: 'takeaway', line: 'Check those three before you look for a mistake.' },
    ],
  });
  assert.equal(explainer.ok, true, JSON.stringify(explainer.cuts[0].failures));
  // Founder pitch, internal update and feature demo each have their own spine.
  for (const id of ['feature-demo', 'social-cut', 'founder-pitch', 'internal-update', 'story', 'non-narrative']) assert.ok(FILM_TYPES[id], id);
  const update = checkStory({ product: 'SubOps', filmType: 'internal-update', targetSeconds: 50, narrative: { change: 'statement intake now reads scanned pages' },
    beats: [{ role: 'context', line: 'Statement intake changed this week.' }, { role: 'demonstration', line: 'A scanned statement is read into rows.' }, { role: 'next-step', line: 'Next week it handles multi-page scans.' }] });
  assert.equal(update.ok, true, JSON.stringify(update.cuts[0].failures));
});

test('a short social cut of a marketing film is judged as a social cut', () => {
  const brief = revolvaMarketing();
  brief.cuts = [
    { id: 'main', targetSeconds: 45, beats: brief.beats },
    { id: 'short', filmType: 'social-cut', targetSeconds: 15, beats: [
      { role: 'hook', line: 'Revolva: a revision landed overnight.' },
      { role: 'demonstration', line: 'Three commitments it breaks, on one screen.' },
      { role: 'payoff', line: 'Owned before stand-up.' },
    ] },
  ];
  delete brief.beats;
  const report = checkStory(brief);
  assert.equal(report.ok, true, JSON.stringify(report.cuts.map((c) => c.failures)));
  assert.deepEqual(report.cuts.map((c) => c.filmType), ['product-marketing', 'social-cut']);
});

test('a non-narrative film states its organizing principle; every film resolves to some form', () => {
  const ambient = { product: 'Lawli', creativeMode: 'abstract', targetSeconds: 30, beats: [{ line: 'Light moves across a desk.' }] };
  assert.ok(rules(checkStory(ambient)).includes('story.principle'));
  ambient.organizingPrinciple = 'One working day, dawn to dusk, in a single slow move across a desk.';
  assert.equal(checkStory(ambient).ok, true);
  assert.ok(rules(checkStory({ product: 'Lawli', filmType: 'docudrama', targetSeconds: 30, beats: [{ line: 'x y' }] })).includes('film.type'));
});

// ---- a planning document's wording validates as written ------------------------------------------------------

test('the seven-role wording of a planning document is accepted, and the product profile supplies the brand name', () => {
  const plan = {
    product: 'ABACare', targetSeconds: 45, cta: { text: 'Explore the demo' },
    narrative: {
      who: 'an ABA clinic owner', moment: 'Monday morning before the first visit', whatGoesWrong: 'an authorization runs out this week',
      problem: 'three scheduled visits are no longer covered', whyItMatters: 'the visits happen but cannot be billed',
      productIntroduction: 'ABACare AI shows the runway on the Today page', how: 'she opens the client and sees units left against visits booked',
      result: 'the renewal is requested before the first uncovered visit',
      beforeState: 'worried about what is about to lapse', afterState: 'clear about the one renewal to request today',
      usefulPayoff: 'see coverage run out before the visit does',
    },
    hookPlan: { firstVisual: 'A visit card with an authorization warning', onScreenText: 'Booked. Not covered.', spokenLine: 'Three visits are booked.', question: 'Are they still covered?' },
    spine: [
      { role: 'hook', start: 0, end: 5, line: 'Three visits are booked. One authorization runs out first.' },
      { role: 'context', start: 5, end: 9, line: 'An owner checks the week before the first family arrives.' },
      { role: 'problem and stakes', start: 9, end: 13, line: 'Three visits would happen without coverage.' },
      { role: 'product introduction', start: 13, end: 20, line: 'ABACare AI puts the runway on the Today page.' },
      { role: 'demonstration', start: 20, end: 31, line: 'She opens the client and reads units left against visits booked.' },
      { role: 'payoff', start: 31, end: 38, line: 'The renewal is requested before the first uncovered visit.' },
      { role: 'call to action', start: 38, end: 45, line: 'Explore the demo.' },
    ],
  };
  const report = checkStory(plan);
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
  assert.equal(report.productProfile, 'abacare');
  assert.deepEqual(rolesOf({ storyRole: 'problem and stakes' }), ['problem']);
  // Naming a different product in the introduction is caught.
  plan.spine[3].line = 'The software puts the runway on the Today page.';
  assert.ok(rules(checkStory(plan)).includes('story.product-named'));
});

// ---- a recorded exception is a decision, not a blocked job ---------------------------------------------------

test('a story rule can be waived with a reason; the waiver is logged, and truth rules cannot be waived', () => {
  const brief = revolvaMarketing();
  brief.beats.pop(); // no call to action
  assert.ok(rules(checkStory(brief)).includes('story.cta-last'));
  brief.storyOverrides = [{ rule: 'story.cta-last', reason: 'Owner 2026-11-10: plays inside the product page, which already carries the button.' }];
  const waived = checkStory(brief);
  assert.equal(waived.ok, true, JSON.stringify(waived.cuts[0].failures));
  assert.equal(waived.cuts[0].waived[0].rule, 'story.cta-last');
  brief.storyOverrides = [{ rule: 'story.cta-last', reason: 'because' }];
  assert.ok(rules(checkStory(brief)).includes('override.reason'));
  brief.storyOverrides = [{ rule: 'truth.representation', reason: 'Owner said it is fine to show this as current.' }];
  assert.ok(rules(checkStory(brief)).includes('override.scope'));
  // In the full lint a waiver becomes a warning that names the rule and the reason.
  assert.deepEqual(validate(adSchema, { ...fullSpec(), storyOverrides: [{ rule: 'story.cta-single', reason: 'Owner 2026-11-10: two asks tested on purpose.' }] }), []);
});

// ---- declaring another mode is not a way out -------------------------------------------------------------------

const io = { specDir: '/t', exists: () => true, readJson: () => ({ clips: { C1: { valid: true, clipSeconds: 60, events: { clicks: 0 } } } }) };
const voice = { provider: 'openai', voiceId: 'alloy', model: 'gpt-realtime-2.1-mini', disclosure: 'end card' };
function fullSpec() {
  return {
    id: 'explainer-dodge', title: 'How claims get paid', product: 'ABACare', creativeMode: 'explainer',
    audience: 'Clinic owners', objective: 'Explain claim submission', voice, claims: [], labels: 'SYNTHETIC · NO PHI',
    cta: { text: 'Explore the demo', url: 'https://example.com/demo' },
    narrative: { question: 'How does a claim get paid?', viewerValue: 'know the steps a claim goes through' },
    cuts: [{ id: 'main', ratios: ['16x9'], targetSeconds: 40, beats: [
      { id: 'B1', kind: 'card', storyRole: 'hook', narration: 'Where does a claim go after the visit?' },
      { id: 'B2', kind: 'card', storyRole: 'explanation', narration: 'A claim is checked, then held or released.' },
      { id: 'B3', kind: 'card', storyRole: 'takeaway', narration: 'Know which step yours is waiting on.' },
    ] }],
  };
}
const lint = (spec, brand = {}) => lintSpec(spec, brand, { io, adSchema });
const codes = (result) => result.errors.map((e) => e.code);

test('a general explainer passes, but a product claim inside it still needs evidence and obeys the claim policy', () => {
  const clean = lint(fullSpec());
  assert.equal(clean.ok, true, JSON.stringify(clean.errors));
  const dodge = fullSpec();
  dodge.cuts[0].beats[1].narration = 'ABACare submits every claim to the payer and guarantees approval.';
  const result = lint(dodge);
  assert.equal(result.ok, false);
  assert.ok(codes(result).includes('claim-unmapped'), 'a line that names the product is a product claim in any mode');
  assert.ok(result.errors.some((e) => e.code === 'banned-phrase' && /sent-to-payer/.test(e.message)), 'the product profile applies the payer policy with no brand file');
  assert.ok(result.errors.some((e) => e.code === 'banned-phrase' && /guarantee/.test(e.message)), 'the generic bans apply to every product');
});

test('a captured interface cannot be relabelled as fiction to skip its evidence', () => {
  const spec = fullSpec();
  spec.creativeMode = 'verified-demo';
  spec.filmType = 'explainer';
  spec.cuts[0].beats[1] = { id: 'B2', kind: 'ui', storyRole: 'explanation', truthStatus: 'illustrative', narration: 'Claims are approved here automatically.', ui: { sourceJob: '/t/job', clipId: 'C1' } };
  const result = lint(spec);
  assert.ok(result.errors.some((e) => e.code === 'representation' && /captured product interface/.test(e.message)));
  assert.ok(codes(result).includes('claim-unmapped'));
  assert.equal(beatIsFactual({ kind: 'ui', truthStatus: 'fictional' }, 'fictional-story'), true);
  assert.equal(beatIsFactual({ kind: 'broll', truthStatus: 'fictional' }, 'verified-demo'), false);
});

test('a concept disclosure has to say the thing is not current fact', () => {
  const cut = { id: 'main', beats: [{ id: 'B1', kind: 'broll', truthStatus: 'proposed', narration: 'Imagine planning a week in one glance.' }] };
  const vague = inspectRepresentation({ creativeMode: 'future-vision', labels: 'ABACare Vision', conceptDisclosure: 'The future of scheduling' }, cut);
  assert.ok(vague.some((e) => e.code === 'concept-disclosure'), 'a product name or a slogan is not a disclosure');
  const clear = inspectRepresentation({ creativeMode: 'future-vision', labels: 'Concept: not a current feature' }, cut);
  assert.equal(clear.some((e) => e.code === 'concept-disclosure'), false);
  // Proposed capability needs the disclosure in any mode, not only the vision ones.
  assert.ok(inspectRepresentation({ creativeMode: 'explainer', labels: 'Brand film' }, cut).some((e) => e.code === 'concept-disclosure'));
});

// ---- the product profile ----------------------------------------------------------------------------------------

test('product policy comes from the profile and the brand file, not from shared code', () => {
  assert.equal(productProfile('ABACare AI').id, 'abacare');
  assert.equal(productProfile('Rexa'), null);
  const merged = withProductProfile({ product: 'ABACare', claimPolicies: [], disclosure: { required: false } }, { product: 'ABACare' });
  assert.equal(merged.disclosure.required, true, 'a brand file cannot switch off its product profile');
  assert.deepEqual(merged.disclosure.mustInclude, ['synthetic', 'no phi']);
  assert.ok(merged.claimPolicies.includes('healthcare-payer'));
  assert.deepEqual(validate(brandSchema, { id: 'rexa', product: 'Rexa', colors: { primary: '#101c3d', foreground: '#ffffff', background: '#101c3d', accent: '#ffd166' }, fonts: { display: 'Inter', body: 'Inter' }, safeZones: {}, forbiddenNames: [], budgets: { elevenlabsCredits: 0, openaiUsd: 1 }, deliver: { dir: '/t/deliver' }, loudness: { social: -14, web: -16 }, productNames: ['Rexa'], disclosure: { required: false }, generatedPeople: 'adults-only' }), []);

  // ABACare: the label rule holds with an empty brand file.
  const unlabelled = fullSpec();
  unlabelled.labels = 'REAL PRODUCT ONLY';
  assert.ok(lint(unlabelled).errors.some((e) => e.code === 'label' && /no phi/.test(e.message)));
  // Another product is not asked for a health disclosure, and not held to payer wording.
  const rexa = fullSpec();
  rexa.product = 'Rexa'; rexa.labels = '';
  rexa.cuts[0].beats[1].narration = 'Insurers reimburse a claim after review.';
  const other = lint(rexa);
  assert.equal(other.ok, true, JSON.stringify(other.errors));
  assert.ok(DEFAULT_BANNED.every((b) => !/payer|hipaa/i.test(b.id)), 'shared defaults name no industry');
  assert.ok(CLAIM_POLICIES['healthcare-payer'].length >= 3);
});

test('generated people follow the product policy and are always classified in a film about the current product', () => {
  const withPerson = (extra = {}) => {
    const s = fullSpec();
    s.product = 'Revolva'; s.labels = 'Brand film';
    s.cuts[0].beats[1] = { id: 'B2', kind: 'broll', storyRole: 'explanation', narration: 'A coordinator reads the plan.', broll: { provider: 'openai-image', prompt: 'A coordinator at a desk reading a printed plan in morning light.' }, ...extra };
    return s;
  };
  assert.equal(lint(withPerson()).ok, true, 'allowed by default outside a product demo');
  assert.ok(codes(lint(withPerson(), { generatedPeople: 'none', product: 'Revolva' })).includes('broll-people'));
  const child = withPerson();
  child.cuts[0].beats[1].broll.prompt = 'A child at a kitchen table doing homework with a parent.';
  assert.ok(codes(lint(child, { generatedPeople: 'adults-only', product: 'Revolva' })).includes('broll-people'));
  const demo = withPerson();
  demo.creativeMode = 'verified-demo'; demo.filmType = 'explainer';
  assert.ok(lint(demo).errors.some((e) => e.code === 'representation' && /generated person/i.test(e.message)));
  demo.cuts[0].beats[1].truthStatus = 'illustrative';
  assert.equal(lint(demo).errors.some((e) => e.code === 'representation'), false);

  // The frame reviewer keeps the people finding when the product restricts people, and drops it otherwise.
  const verdict = { frames: [{ label: 'F1', issues: [{ category: 'people-or-children', severity: 'high', detail: 'a child', evidence: 'child' }] }], overall: { labelPresentWhereRequired: true } };
  assert.equal(evaluate(verdict, { spec: { creativeMode: 'verified-demo' }, brand: { generatedPeople: 'adults-only' } }).ok, false);
  assert.equal(evaluate(verdict, { spec: { creativeMode: 'verified-demo' }, brand: {} }).ok, true);
  // An invented interface is still a defect in a factual form.
  const fake = { frames: [{ label: 'F1', issues: [{ category: 'fabricated-ui', severity: 'high', detail: 'not captured', evidence: 'chart' }] }], overall: { labelPresentWhereRequired: true } };
  assert.equal(evaluate(fake, { spec: { creativeMode: 'explainer' }, brand: {} }).ok, false);
  assert.equal(evaluate(fake, { spec: { creativeMode: 'future-vision', conceptDisclosure: 'concept' }, brand: {} }).ok, true);
});

// ---- thresholds follow the real length ---------------------------------------------------------------------------

test('a cut is judged by how long it runs, and long films are allowed', () => {
  const brief = revolvaMarketing();
  brief.targetSeconds = 24; // declared as a teaser, but the script runs far longer
  const report = checkStory(brief);
  assert.equal(report.cuts[0].compact, false, 'a script that runs past the teaser length is not a teaser');
  const long = { ...fullSpec() };
  long.cuts[0].targetSeconds = 240;
  assert.deepEqual(validate(adSchema, long), [], 'a four-minute film is a valid spec');
});

// ---- gaps found by an independent review of this gate ---------------------------------------------------------

test('a label does not turn a product claim into fiction, in any mode', () => {
  // "illustrative" on a card that says what the product does: still a claim, still checked.
  const spec = fullSpec();
  spec.cuts[0].beats[1] = { id: 'B2', kind: 'card', storyRole: 'explanation', truthStatus: 'illustrative', narration: 'ABACare submits every claim to the payer, guarantees approval, and is HIPAA certified.' };
  for (const mode of ['explainer', 'verified-demo']) {
    spec.creativeMode = mode; spec.filmType = 'explainer';
    const result = lint(spec);
    assert.equal(result.ok, false, mode);
    assert.ok(codes(result).includes('claim-unmapped'), `${mode}: evidence is still required`);
    for (const id of ['sent-to-payer', 'guarantee', 'hipaa-status']) assert.ok(result.errors.some((e) => e.code === 'banned-phrase' && e.message.includes(id)), `${mode}: ${id}`);
  }
  // An invented film that names the product is held to the claim wording too.
  const story = fullSpec();
  story.creativeMode = 'fictional-story'; story.labels = 'SYNTHETIC · NO PHI · a fictional story';
  story.narrative = { persona: 'a clinic owner', situation: 'a late evening at the desk', emotionalBefore: 'tired and behind', emotionalAfter: 'relieved and caught up' };
  story.cuts[0].beats = [{ id: 'B1', kind: 'card', narration: 'ABACare is HIPAA certified and guarantees approval by the payer.' }];
  const fiction = lint(story);
  assert.ok(fiction.errors.some((e) => e.code === 'banned-phrase' && e.message.includes('guarantee')));
  assert.ok(fiction.errors.some((e) => e.code === 'banned-phrase' && e.message.includes('hipaa-status')));
  // A scene that does not speak about the product stays free.
  assert.equal(beatIsFactual({ kind: 'broll', truthStatus: 'illustrative', narration: 'A family arrives at the clinic.' }, 'verified-demo', ['abacare']), false);
  assert.equal(beatIsFactual({ kind: 'card', truthStatus: 'illustrative', narration: 'ABACare files it for you.' }, 'explainer', ['abacare']), true);
});

test('a product named with an ordinary word is matched as a name, not as the word', () => {
  const spec = fullSpec();
  spec.product = 'Linear'; spec.labels = 'Brand film'; spec.creativeMode = 'documentary';
  spec.cuts[0].beats[1].narration = 'Growth in a young company is rarely linear.';
  assert.equal(lint(spec).ok, true, JSON.stringify(lint(spec).errors));
  spec.cuts[0].beats[1].narration = 'Teams plan the week in Linear.';
  assert.ok(codes(lint(spec)).includes('claim-unmapped'));
});

test('the product profile is found however the name is spaced, and a broken profile file stops the run', () => {
  for (const name of ['ABA Care', 'abacareai', 'Abacare, Inc.', 'ABACare AI']) assert.equal(productProfile(name)?.id, 'abacare', name);
  assert.equal(withProductProfile({ id: 'abacare-channel', product: 'ABACare AI' }, { product: 'Our platform' }).disclosure.required, true, 'found from the brand file when the spec uses another name');
  assert.equal(productProfile('Abacus'), null);
});

test('a waiver is logged by the full lint, covers capitalised rule ids, and can be a wildcard', () => {
  const spec = fullSpec();
  spec.product = 'Revolva'; spec.labels = 'Brand film';
  delete spec.narrative;
  assert.ok(lint(spec).errors.some((e) => e.rule === 'story.narrative'));
  spec.storyOverrides = [{ rule: 'story.narrative', reason: 'Owner 2026-11-10: cut from an approved film, brief is on that issue.' }];
  assert.deepEqual(validate(adSchema, spec), []);
  const waived = lint(spec);
  assert.equal(waived.ok, true, JSON.stringify(waived.errors));
  assert.ok(waived.warnings.some((w) => w.code === 'story-override' && /story\.narrative waived: Owner 2026-11-10/.test(w.message)));
  assert.deepEqual(validate(adSchema, { ...spec, storyOverrides: [{ rule: 'story.narrative.emotionalBefore', reason: 'Owner 2026-11-10: a reference clip, no arc intended.' }] }), []);
  spec.storyOverrides = [{ rule: 'story.*', reason: 'Owner 2026-11-10: legacy spec, predates the story gate.' }];
  spec.cuts[0].beats.forEach((b) => { delete b.storyRole; });
  const blanket = lint(spec);
  assert.equal(blanket.ok, true);
  assert.ok(blanket.warnings.filter((w) => w.code === 'story-override').length >= 2, 'every waived rule is listed');
});

test('each film type rejects a film that lacks its own spine', () => {
  const beat = (role, line) => ({ role, line });
  const missing = {
    'feature-demo': [[beat('demonstration', 'Revolva lists the affected commitments.')], 'story.context'],
    'social-cut': [[beat('demonstration', 'Revolva: three commitments on one screen.')], 'story.hook'],
    'founder-pitch': [[beat('hook', 'Plans change overnight.'), beat('cta', 'Talk to us.')], 'story.problem'],
    'internal-update': [[beat('demonstration', 'A scan becomes rows.')], 'story.context'],
    explainer: [[beat('explanation', 'Timing moves a total.')], 'story.hook'],
  };
  for (const [filmType, [beats, rule]] of Object.entries(missing)) {
    const report = checkStory({ product: 'Revolva', filmType, targetSeconds: 40, beats });
    assert.ok(rules(report).includes(rule), `${filmType}: expected ${rule}, got ${rules(report).join(', ')}`);
  }
});

test('a muted opening is planned by its on-screen text, and a planned concept shot is not a capture', () => {
  const muted = revolvaMarketing();
  muted.hookPlan = { visual: 'A revision notice on a delivery plan', onScreen: 'One revision. Which commitments broke?', viewerQuestion: 'Which commitments did it break?' };
  muted.beats[0] = { role: 'hook', onScreen: 'One revision. Which commitments broke?' };
  const report = checkStory(muted);
  assert.equal(report.ok, true, JSON.stringify(report.cuts[0].failures));
  const vision = checkStory({ product: 'Revolva', creativeMode: 'future-vision', conceptDisclosure: 'Concept: not a current feature', targetSeconds: 40,
    narrative: { persona: 'an operations lead', situation: 'a planning morning next year', emotionalBefore: 'guarded about the week', emotionalAfter: 'curious and hopeful' },
    beats: [{ role: 'demonstration', truthStatus: 'proposed', line: 'Imagine the plan repairing itself.' }] });
  assert.equal(vision.ok, true, JSON.stringify(vision.cuts[0].failures));
  assert.throws(() => checkStory({ product: 'Revolva', beats: {} }), /beats must be an array/);
  assert.throws(() => checkStory(null), /JSON object/);
});

test('capture gates follow the cut being judged', async () => {
  const { requiredGates, hasCapture } = await import('../kit/marketing/lib/gates.mjs');
  const spec = { creativeMode: 'hybrid', cuts: [
    { id: 'main', ratios: ['16x9'], beats: [{ kind: 'ui' }, { kind: 'broll' }] },
    { id: 'mood', ratios: ['9x16'], beats: [{ kind: 'broll' }] },
  ] };
  assert.equal(hasCapture(spec, '16x9'), true);
  assert.equal(hasCapture(spec, '9x16'), false);
  assert.ok(requiredGates(spec, '16x9').includes('pointer'), 'the cut with captured interface keeps its capture gates');
  assert.equal(requiredGates(spec, '9x16').includes('pointer'), false, 'a generated-only cut is not asked for a pointer trace it cannot have');
  assert.equal(requiredGates(spec, '9x16').includes('integrity'), false);
  const brandWithMode = (mode) => ({ id: 'x1', product: 'X', colors: { primary: '#000000', foreground: '#ffffff', background: '#000000', accent: '#ffffff' }, fonts: { display: 'Inter', body: 'Inter' }, safeZones: {}, forbiddenNames: [], budgets: { elevenlabsCredits: 0, openaiUsd: 1 }, deliver: { dir: '/t' }, loudness: { social: -14, web: -16 }, disclosure: { required: true, mode } });
  assert.deepEqual(validate(brandSchema, brandWithMode('end-card')), []);
  assert.ok(validate(brandSchema, brandWithMode('film-level')).length > 0, 'only disclosure modes the narration gate accepts');
});
