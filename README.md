# Sowline India

**Crop supply–demand matching for all of India.** Normalise what the country
will buy into kilograms per district per ISO week, subtract what is actually
coming, and shift the difference *backwards through the crop calendar* into a
sowing date a farmer can act on — capped, so the advice cannot itself become
the next glut.

Built against `uploads/agri-supply-demand-spec.md`.

---

## Run it

```bash
npm install
npm run dev          # http://localhost:3000
```

**No configuration is required.** With no Firebase project and no Gemini key,
the app generates a deterministic seed bundle, runs the gap engine in-process,
and serves the full product. Every screen is labelled `Seeded demo data` — it
never presents generated numbers as a live feed.

```bash
npm run typecheck    # tsc --noEmit
npm run build        # production build (standalone output)
npm run seed:dry     # print what a Firestore seed would write, write nothing
npm run seed         # write reference + seed data to Firestore, then run the engine
npm run rules:deploy # firebase deploy --only firestore:rules,firestore:indexes,storage
```

With `GEMINI_API_KEY` set and a dev server running, the two intake paths can be
checked for real. Both hit the live API and cost a few cents:

```bash
npm run smoke:voice   # walk a whole declaration in Tanglish over a real ephemeral token
npm run smoke:advisor # walk a crop-advice call: does it open itself, warn off a full crop, propose?
npm run fixtures      # generate the document fixtures (needs python3 + Pillow)
npm run smoke:docs    # extract them and compare against known truth
```

`npm run smoke:context` needs neither a key nor a server — it checks the block
the advisor is handed, that the crowding table reconciles with `/allocations`,
and that the three-day revert window opens and shuts where it claims to.

Pass a base URL if the dev server is not on port 3000:
`npm run smoke:voice -- http://localhost:3001`.

---

## The three surfaces

| Route | Surface | Who |
| --- | --- | --- |
| `/dashboard` | **C** · National gap dashboard | Agri department, press, judges |
| `/farmer` | **B** · Farmer app | Smallholders, native language, low-end Android |
| `/buyer` | **A** · Demand portal | Retail, quick-commerce, FPOs, mandi committees |
| `/trust` | — | Consent, privacy, and the limits stated up front |

---

## The engine

`lib/engine/index.ts` is a pure function from data to data — it never touches
Firestore, which is what makes it testable and what lets the demo run on
in-memory arrays. Six steps, matching the spec:

1. **Normalise demand** — done upstream by `/api/demand/map`: free-text product
   names → canonical commodity, one model call per *distinct string*, cached in
   `nameMappings`. Pack sizes ("500g Pack") fold into the quantity.
2. **Project demand forward** — `observed(last year, same week) × yoy growth ×
   festival multiplier`, floored by committed forward orders. A v0 baseline,
   labelled as one.
3. **Project supply** — `declared + arrivals × (1 − declaration_coverage)`.
   Getting this blend wrong makes every number downstream nonsense, so
   declaration coverage is displayed next to the numbers it qualifies.
4. **Gap** — `demand − supply`, and `coverage_ratio = supply / demand`.
5. **Backward-shift into a sowing window** — `sow_week = harvest_week −
   ceil(days_to_first_harvest / 7)`, skipped if that week is in the past or
   outside the agronomic window. **Skipping is a feature**: skipped gaps are
   listed with their reason, never silently dropped.
6. **Allocate under a cap** — each opportunity releases only **80%** of its
   shortfall. Farmers are ranked by `revenue × confidence × (1 − risk) ×
   diversification`, take at most three, and the pool visibly depletes.

### Three decisions worth knowing about

**Opportunities are cluster-level, gaps are district-level.** Demand pools in
districts that grow nothing — Azadpur in Delhi is Asia's largest vegetable
market and Delhi grows almost no tomato. A per-district opportunity would tell
a Delhi catchment to sow tomato in Delhi. So opportunities anchor on districts
that can actually grow the crop (`lib/data/belts.ts`) and aggregate the gap
over a 150 km catchment, claimed greedily largest-first so the same tonnage is
never sold to two sets of farmers.

**Coverage is reported twice per cell.** A production belt out-produces its own
town by design; its output is already spoken for elsewhere. Colouring the map
by district coverage painted every belt permanently red and every city
permanently green. The map and heat grid are therefore coloured by
`clusterCoverageRatio` — the catchment, which is the market a farmer actually
faces — with the district figure still shown in the readout.

**Risk and confidence are separate axes.** Risk is what the market can do to a
farmer: perishability and price-band width. Confidence is how much we know:
source count, declaration coverage, mandi observations. Folding coverage into
both put 88 of 109 opportunities into "high risk", and a label on everything is
a label on nothing.

---

## Data model

`lib/firebase/schema.ts` is the single source of truth. Firestore is not
Postgres, so the spec's DDL is translated under three rules:

1. **Denormalise the join keys, never the facts.** A supply declaration carries
   `districtId` and `commodityId` because the engine aggregates by those. It
   does not carry the farmer's name.
2. **Composite string IDs where the tuple is the identity.** A gap bucket is
   `${commodityId}__${districtId}__${year}W${week}`, so a rerun overwrites and
   the engine is idempotent for free.
3. **Aggregates are written, not computed on read.** Clients read `gapBuckets`
   and `opportunities`. Nobody scans `demandSignals`.

Security lives in `firestore.rules` and `storage.rules` and is worth reading —
every privacy claim on `/trust` corresponds to a rule, not to a policy page.

---

## Voice and vision

Both are **alternate paths, never the critical path**. The typed form is the
product; voice and photo fill the same draft and go through the same confirm
step and the same write.

- **Voice** — Gemini Live, speech-to-speech, in `lib/gemini/useGeminiLive.ts`.
  The browser gets a single-use ephemeral token from `/api/live/token`; the real
  key never leaves the server. Function tools (`set_plot_area`, `set_crop`, …)
  are named after the form's own fields, so the form fills itself as the farmer
  speaks. The model auto-detects the language — no language code is pinned,
  because a farmer switching between Tamil and English mid-sentence is normal.

  Two things had to be handled rather than assumed. The model **has no clock**,
  so `intakeSystemPrompt` prints a pre-resolved table of relative dates ("three
  weeks ago = 2026-07-18") and the model reads a row instead of doing
  arithmetic — asked to compute it, it was a week out, and a week moves the
  harvest week. And **tool calling is not reliable run to run**: in one measured
  run all six tools fired in order, in the next every value was spoken correctly
  aloud and two tools fired. So `/api/intake/parse` re-reads the fields out of
  the transcript as a backstop, merged *under* the tool calls and under anything
  typed — it can only fill gaps, never overwrite an answer.

  `npm run smoke:voice` walks a whole five-answer declaration in Tanglish over a
  real ephemeral token, using typed turns in place of mic audio. Run it before
  changing the live model: a model can stay available while quietly losing tool
  calling, which is invisible in the model list and empties the form.
- **Advice** — the same Live transport, a different job. `components/CropAdvisor.tsx`
  sits beside the recommendations on *What to sow* and opens the conversation
  itself, in Kongu spoken Tamil, naming the crop it would pick and why. Intake
  **collects** and therefore asks; this one **advises** and therefore has to
  already know — so `lib/advisor/context.ts` assembles the farmer's land, water,
  soil, district seasons, every offer on screen, what is closed to them and how
  crowded each crop already is, and hands it over whole at session open. No
  query tools: a live audio model that waits on a round trip is a pause the
  farmer hears.

  It has **no accept tool**, and that absence is the design. It calls
  `propose_accept`, the screen shows a chip with the crop, the acres and the
  reason, and the farmer taps — the same write path the button uses. A voice
  model that could claim acres on a mishear would undo the one promise the
  product rests on.

  Two things it must be able to do are *say no*: `flag_oversupply` when the
  crowding table (shared with `/allocations` via `lib/market.ts`, so the two
  cannot disagree in front of a farmer who can see both) shows a crop nearly
  taken, and `show_blocked` when the answer is that the land cannot carry the
  crop — always with what would change it, naming the farmer's own drip plot
  where they have one.

  `npm run smoke:context` checks all of that with no API key and no network.
  `npm run smoke:advisor` walks a real session; it caught the model steering a
  farmer off a 96%-claimed crop in words while never firing the tool that pins
  the warning to the screen, which is invisible from the transcript alone.
- **Vision** — `/api/vision/extract` reads a Soil Health Card or mandi bill into
  structured JSON with per-field confidence. **Nothing is written.** Extracted
  values are shown for confirmation first; an OCR that silently reads pH 8.4 as
  3.4 would produce a fertiliser plan that damages soil. The soil chemistry
  rides along on the draft with `soilSource` and `soilConfirmedByFarmer`, so
  nothing downstream can mistake a photo for a typed value — and it does not
  gate the save button, because a farmer without a card must still be able to
  declare.

  `npm run fixtures && npm run smoke:docs` checks it against known truth over
  three generated documents: a clean bilingual card, a Tamil mandi bill shot
  crooked with glare, and the same card blurred past legibility. The third must
  come back `unreadable` — a fixture that has to fail is the whole safety
  argument for this route.

Both degrade to a labelled message when `GEMINI_API_KEY` is absent.

### The voice orb

`components/VoiceOrb.tsx` — a canvas blob whose outline is a sum of three sine
harmonics at coprime lobe counts, traced as a closed Catmull-Rom spline. Drawn
with three marks and no more: a translucent fill, a hairline contour, and one
fainter echo contour behind it.

Time modulates the harmonics' **amplitude, never their phase**, so the shape
swells and settles in place and nothing travels around the circle — that is
what keeps it from reading as a spinner. Speeds are radians per millisecond
against a `t` that advances ~16 per frame; get that scale wrong and the
outline aliases into a violent spin rather than animating.

It warms toward terracotta when the farmer speaks and cools toward sage when
the assistant answers — a continuous crossfade, not a flip — so a farmer who
cannot read the interface can still tell whose turn it is. Colours come from
live CSS custom properties, so it follows the theme rather than carrying its
own palette.

---

## Design

Tokens in `app/globals.css`, derived from the Organic design system kept in
`reference/_ds` — cream ground, terracotta accent, sage second accent,
over-rounded shapes, Fraunces over Figtree. Extended with a signal ramp
(deficit / balanced / glut) the dashboard needs.

Icons are Lucide throughout. There are no emoji or text glyphs standing in for
icons anywhere in the product.

The deficit/glut colour direction is deliberate and is the opposite of the
reflex: **shortfall reads green** because for a farmer it is opportunity, and
**surplus reads red** because it is the signal to stay out. The audience for
that colour is the person deciding what to sow.

---

## Deploying

```bash
# Firestore rules and indexes
firebase use <project-id>
npm run rules:deploy

# Seed a real project (needs GOOGLE_APPLICATION_CREDENTIALS)
npm run seed

# Cloud Run
gcloud run deploy sowline --source . --region asia-south1 --allow-unauthenticated
```

`Dockerfile` builds the standalone output and runs as a non-root user on
`$PORT`. Docker is not built or run by any script here — trigger it yourself.

---

## Layout

```
app/            routes: /, /dashboard, /farmer, /buyer, /trust, /api/*
components/     Shell, IndiaMap, HeatGrid, CobwebChart, VoiceOrb, VoiceIntake, ui
lib/
  data/         geography (28 states, 8 UTs, 142 districts), commodities,
                crop calendar, festivals, production belts
  engine/       the six steps, pricing/risk/confidence, catchment geometry
  firebase/     schema (the source of truth), client + admin SDK handles
  gemini/       model config, the intake tool contract, the Live hook
  seed/         deterministic seed bundle
  store.ts      the one read path — live Firestore, or the local seed
llm-wiki/       compounding notes on this codebase; read CLAUDE.md first
reference/      the original Sowline mockup and the Organic design system
scripts/seed.ts
firestore.rules  firestore.indexes.json  storage.rules  firebase.json
```

---

## What this is not

Stated here as well as on `/trust`, because a reviewer should not have to find
it: this is **not** a buyer commitment, **not** an ML forecast, **not** a supply
registry, and **not** identity infrastructure. Declaration coverage is a few
percent and is shown on every screen. Price is always a band, never a point.
No Aadhaar and no land records are collected, ever.

---

## Hackathon

Submitted for **Build with AI: Code for Communities** — Tech for Good 2026,
GDG Coimbatore (Aug 8–9, 2026, GRD College).

- [`PROPOSAL.md`](./PROPOSAL.md) — architecture proposal (Ideation-Phase submission)
- [`MILESTONES.md`](./MILESTONES.md) — milestone checklist
- [`/docs`](./docs) — design notes, diagrams, research

Application code lives at the repository root (`app/`, `components/`, `lib/`),
per Next.js convention, rather than under `/src`.
