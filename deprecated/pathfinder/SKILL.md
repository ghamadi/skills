---
name: pathfinder
description: >-
  Produces a self-contained plan folder for **one scoped change** — `context.md`, a design doc explaining the approach,
  key decisions, and data flow with concise reasoning, plus `path.json`, exhaustive step-by-step implementation steps
  derived from it. Use this whenever the user wants to plan, design, or scope a non-trivial change before writing code —
  "plan the X work", "how should I implement X", "design an approach for X", "write up an implementation plan", "scope
  this feature", "make a plan for the refactor" — or to plan one part of an `architect` design doc. Prefer this over
  ad-hoc planning whenever the user wants a plan they can hand to another agent or revisit later. Work spanning a whole
  feature, ticket, or PR belongs to `architect` first; pathfinder plans a single coherent change. Delivers
  `<plan-name>/` to a plans directory and then STOPS — it does not begin implementing unless the user explicitly asks.
---

# Pathfinder

Turn one scoped change into a **plan folder** a person or another agent can act on:

```
<plan-name>/
  context.md   ← the why: approach, key decisions, architecture, data/control flow
  path.json    ← the what: exhaustive, ordered steps derived from context.md
```

`context.md` is for whoever decides _whether the approach is right_; `path.json` is small, ordered, unambiguous units of
work for whoever _executes_ it. Get `context.md` right first — `path.json` faithfully decomposes it and is never where a
new decision first appears.

Your job ends when the folder is written and you've printed a short pointer to it. **Do not start implementing** unless
the user explicitly asks — planning and doing are separate acts, and the user may want to review the plan first.

## Two modes

Pathfinder always plans one coherent change; where that change's design comes from decides how much of the thinking is
yours.

- **Standalone** — no design doc. You investigate, settle the approach with the user, and `context.md` is where the
  design happens.
- **Design-driven** — the user points you at a `design.md` from `architect`, or names a part of one. The architecture
  and the cross-part contracts are already settled. You plan _one part_ faithfully; you don't redesign it.

When there is a `design.md`, read it in full before anything else. Its **Seam contracts** section is binding: every
path, signature, and name it pins is a fact your plan builds on, not a suggestion. Sibling parts are being built against
those same contracts by agents that will never see your plan.

---

## The workflow

Work these phases in order. Don't skip investigation or clarification — a plan built on guesses is worse than none,
because it looks authoritative while being wrong.

### 1. Understand the request and investigate

A plan is a _diff against reality_, so know the reality before planning.

- **Read the relevant code.** Trace the modules, functions, data structures, and boundaries the change touches; read the
  actual files rather than assuming how they work. For a broad sweep, an `Explore` subagent maps the territory without
  burning your own context.
- **Find the existing patterns.** Follow the grain of how this codebase already does similar things instead of importing
  foreign conventions.
- **Identify the seams.** Where does the change plug in — which interfaces, call sites, and tests will have to move?

Scale the investigation to the change: a one-file tweak needs a glance, a cross-cutting refactor a real survey.

### 2. Check the scope

Now that you know what the change involves, test it: **could you drop half of it and still have something worth
shipping?** If so, it's two changes wearing one name — link expiry and a viewer audit trail are each valuable alone.
Layers don't count: a column, the DTO field that carries it, and the component that renders it are one change when all
three serve the same single purpose. A second test catches the rest: does the change introduce a module boundary that
later, separate work will build on?

If it fails either, say so in a line and ask whether to run `architect` first or proceed anyway — then honor the answer.
The user often knows the work is big and wants the plan regardless; this is a flag, not a gate. Raise it once and move
on.

The flag is worth raising because a plan spanning a whole ticket has to invent an architecture _and_ decompose it in a
single pass. The architecture reliably gets the thinner half of the attention, and what comes out is a long run of
faithful steps with no spine — code that works and reads like sediment.

In design-driven mode, a part that fails this test is a hole in the design; step 4 says what to do about it.

### 3. Resolve the destination

**Standalone:** `.claude/plans/<plan-name>/` at the project root (the git root, or the top-most directory containing the
project). Derive `<plan-name>` from the change: short, kebab-case, descriptive (`feed-dedup`, `auth-rate-limit`).

**Design-driven:** nest beside the design, so the feature travels as one unit and the parts stay ordered on disk:

```
.claude/plans/<feature>/
  design.md
  01-<part-name>/{context.md, path.json}
  02-<part-name>/{context.md, path.json}
```

`NN` matches the part's position in the design's sequence.

Either way the files inside are always `context.md` and `path.json`, and nothing else — that's what lets an executor
open a folder it's never seen and know where to look. Create directories as needed. If the user names another location,
honor it and carry the whole convention across: the plan folder still nests inside, and a part still keeps its `NN-`
prefix.

If the plan folder already exists, don't overwrite it silently — it may be a prior plan, possibly one already
part-executed. Ask whether to replace it or pick another name.

### 4. Grill the user on what's still open

Some decisions a plan surfaces are the user's to make, not yours. When the request leaves a genuine, load-bearing
unknown open — a missing constraint or success criterion ("add caching" — cache _what_, invalidated _how_, bounded by
_what_?), two goals that can't both hold or a request that conflicts with the code, or an ambiguity where different
readings yield materially different plans — close it before writing anything. If the investigation already answered what
you need, skip this; don't interrogate the user over decisions you can reasonably make yourself.

The methodology lives in dedicated skills, marked `disable-model-invocation` — so you can't fire them like a normal
skill. Read the one you pick and run the interview exactly as it prescribes:

- **Default — `batch-grill-me`** (`~/.claude/skills/batch-grill-me/SKILL.md`): asks every currently-answerable question
  each round, then recomputes the frontier as answers arrive. Fewest round-trips for a broad decision set.
- **Sequential — `grill-me`** (methodology in `~/.claude/skills/grilling/SKILL.md`): one question at a time, each answer
  shaping the next. Only when the decisions are so tightly dependent that batching would force you to guess, or when the
  user asks for it.

**In design-driven mode, keep this to a minimum.** The load-bearing decisions were settled with the user while the
design was written; re-opening them is exactly how a part drifts off the spine. Ask only about something genuinely
interior to this part that the design left open and you can't reasonably decide.

**When the design and the code disagree**, never edit `design.md` — it's the spine every sibling part is being built
against, and the agent with the narrowest view is the wrong one to move it. What you do instead turns on whether this
part can still be planned:

- **Blocking** — a contract this part needs was never pinned, or the part is really two. Write nothing, name the gap,
  hand it back.
- **Non-blocking** — the gap lands in a different part, or a pinned contract is unimplementable as literally written but
  has an obvious minimal-deviation form (the codebase injects dependencies through constructors, so a pinned free
  function becomes a method of the same name and signature at the same path). Plan the part, take the smallest deviation
  that preserves the contract's _purpose_, and record both the deviation and the gap where the user will see them.

Most disagreements are non-blocking. Stopping on one is expensive, so reserve it for the case where planning would mean
guessing at something the design was supposed to decide.

### 5. Write `context.md`

Write `context.md` first — this is where the thinking happens.

Follow the structure in **`references/templates.md`** — read it now if you haven't; it covers both files and has a
worked example. The essence:

- Lead with the **problem and goal** — what's changing and why, briefly.
- Spend the bulk on the **approach and key decisions**: the changes, the architecture, the high-level data/control flow.
  Give the _why_ for each significant decision in a sentence or two, and where you rejected a plausible alternative,
  name it and say why the chosen path won — that's the reasoning a reviewer most needs and most often can't reconstruct
  alone.
- Include **only load-bearing snippets** — a type signature that pins an interface, a tricky transform, a config shape.
  Skip boilerplate the executor can obviously fill in.
- Name the **affected files/areas**, the **risks or open questions**, and the **testing approach** at a high level.

Altitude test: a reviewer should finish knowing _what you'll do and why_ — able to challenge a specific decision,
without a line-by-line script. If it reads like source code with prose captions, it's too low; if it reads like a vague
mission statement, it's too high.

**In design-driven mode, reference `../design.md`; don't restate it.** Its job is what's true of _this part_ that the
design didn't already say — the interior decisions you made, the files you found, this part's testing. Drop sections the
design already covers, and point at it for the rest. Repeating the architecture gives it a second copy that can silently
disagree with the first.

### 6. Derive `path.json`

Now decompose `context.md` into `path.json`. This is _transcription, not design_ — every step traces back to something
the markdown already decided. If you find yourself making a new decision here, stop and fix `context.md` first, then
re-derive. (When the JSON wants a step the markdown never mentioned, or the markdown decides something the JSON doesn't
reflect, that mismatch is a hole in the plan — reconcile it in `context.md`. That tension is the feature, not a
nuisance.)

The file is a **JSON array of step objects**, each with exactly these fields:

| field    | type   | meaning                                                                                                                                                                                      |
| -------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`     | number | Sequential, starting at 1, in execution order.                                                                                                                                               |
| `title`  | string | Short imperative label (e.g. "Add `dedupeByUrl` to the feed store").                                                                                                                         |
| `kind`   | string | `"implementation"` — does work that changes the code/system — or `"verification"` — only checks something and changes nothing (runs tests, a linter, a build, or confirms a behavior holds). |
| `action` | string | What must be done for the step to be _complete_: which file, which function, what behavior — specific enough for an agent to execute.                                                        |
| `status` | string | Always `"pending"` on a fresh plan.                                                                                                                                                          |
| `notes`  | string | Extra guidance when `action` alone isn't enough — gotchas, ordering constraints, links to markdown sections. `""` when there's nothing to add.                                               |

`kind` drives how the executor treats a step, so classify honestly:

- **Split doing from checking.** A step that both makes a change _and_ verifies it is two steps — an `implementation`
  step, then a `verification` step after it. Only that split lets the executor treat each correctly.
- **Only verification is skippable.** At execution time a verification step may end up `skipped`; an implementation step
  never can — skipping real work would leave the change half-built. The validator enforces this, so don't mislabel
  load-bearing work as `verification` to make it skippable.
- **Flag expensive verifications in `notes`.** When a check is costly — a full suite, a long build, an external or live
  call — say so, so the executor knows to pause and ask the user before running it rather than hitting a real system
  unprompted.

The other statuses — `in_progress`, `done`, `blocked`, and `skipped` (verification only) — are outcomes the executing
agent records as it walks the plan; never write them into a fresh plan yourself.

Good steps are:

- **Exhaustive and ordered** — cover everything needed to ship the change (tests, migrations, wiring, cleanup — not just
  the interesting code), in an order where each step's prerequisites are already done.
- **One coherent unit each** — completable and checkable on its own. If half an `action` could be done and checked
  without the other half, it's two steps.
- **Concrete** — real files, functions, and types from your investigation. "Update the store" is weak; "Add a
  `dedupeByUrl(items)` method to `filesystem-feed-store.ts` that drops entries whose normalized URL already exists" is a
  step someone can act on.
- **Executable without re-reading all of `context.md`**, but free to point back to it in `notes` for the _why_.

**Close with a consolidation pass.** The executor does exactly what each step says and no more, so over a dozen steps
the code accretes: near-duplicate helpers, a type that should have been shared, scaffolding from step 3 that step 9 made
dead. End the plan with an `implementation` step that re-reads the accumulated diff and consolidates — the `/simplify`
skill is built for exactly this — followed by the verification steps that prove the consolidation broke nothing. Bound
it to the plan's own diff: pre-existing duplication in the neighborhood is a separate change the user hasn't asked for.

Validate before you finish, and fix anything it flags (missing fields, bad status, non-sequential ids, malformed JSON)
until it passes:

```bash
python3 ~/.claude/skills/pathfinder/scripts/validate_plan.py <path-to>/<plan-name>/path.json
```

### 7. Report back

Print a short pointer, nothing more — the plan lives in the files, so don't restate it in chat:

- The plan folder path, first — it's the single path the user hands to `roadrunner`.
- A one-to-two sentence summary of the chosen approach.
- The number of steps in `path.json`.
- A reminder that you haven't started implementing, and an offer to do so or to revise the plan.
