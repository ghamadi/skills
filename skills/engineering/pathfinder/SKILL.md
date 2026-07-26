---
name: pathfinder
description: >-
  Produces a self-contained plan folder — `context.md`, a markdown design doc
  explaining the approach, key decisions, architecture, and data flow with
  concise reasoning, plus `path.json`, exhaustive step-by-step
  implementation steps derived from that markdown. Use this whenever the user
  wants to plan, design, or scope a non-trivial change before writing code —
  phrasings like "plan the X work", "how should I implement X", "design an
  approach for X", "write up an implementation plan", "scope this feature",
  "make a plan for the refactor", or when a task clearly spans multiple
  files/systems and jumping straight to code would be premature. Prefer this
  skill over ad-hoc planning whenever the user asks for a plan they can hand to
  another agent or revisit later. Delivers <plan-name>/ to a plans directory and
  then STOPS — it does not begin implementing unless the user explicitly asks.
---

# Implementation Planner

Turn a change request into a **plan folder** a person or another agent can act on:

```
<plan-name>/
  context.md   ← the why: approach, key decisions, architecture, data/control flow
  path.json    ← the what: exhaustive, ordered steps derived from context.md
```

`context.md` is a design doc for whoever decides *whether the approach is right*;
`path.json` is small, ordered, unambiguous units of work for whoever *executes*
it. Get `context.md` right first — `path.json` faithfully decomposes it and is
never where a new decision first appears.

Bundling both under one folder lets the plan travel as a unit: the executor is
handed a single path (`roadrunner .claude/plans/<plan-name>`) and finds the *why*
and the *what* inside, under fixed names it never has to guess at.

Your job ends when the folder is written and you've printed a short pointer to
it. **Do not start implementing** unless the user explicitly asks — planning and
doing are separate acts, and the user may want to review the plan first.

---

## The workflow

Work these phases in order. Don't skip investigation or clarification — a plan
built on guesses is worse than none, because it looks authoritative while being
wrong.

### 1. Resolve the destination directory

The folder goes in **`.claude/plans/`** at the project root (the git root, or the
top-most directory that contains the project), giving
`.claude/plans/<plan-name>/{context.md,path.json}`. Create the directories if
they don't exist.

Exception: if the user names another location — as an argument
(`/pathfinder docs/plans`) or in conversation — honor it, still nesting a
`<plan-name>/` folder inside. Absent an explicit request, always use
`.claude/plans/`.

If `<plan-name>/` already exists, don't overwrite it silently — it may be a prior
plan, possibly one already part-executed. Ask whether to replace it or pick
another name.

### 2. Understand the request and investigate

A plan is a *diff against reality*, so know the reality before planning.

- **Read the relevant code.** Trace the modules, functions, data structures, and
  boundaries the change touches; read the actual files rather than assuming how
  they work. For a broad sweep, an `Explore` subagent maps the territory without
  burning your own context.
- **Find the existing patterns.** Follow the grain of how this codebase already
  does similar things instead of importing foreign conventions.
- **Identify the seams.** Where does the change plug in — which interfaces, call
  sites, and tests will have to move?

Scale the investigation to the change: a one-file tweak needs a glance, a
cross-cutting refactor a real survey.

### 3. Grill the user when the request is underspecified

Some decisions a plan surfaces are the user's to make, not yours. When the
request leaves a genuine, load-bearing unknown open — a missing constraint or
success criterion ("add caching" — cache *what*, invalidated *how*, bounded by
*what*?), two goals that can't both hold or a request that conflicts with the
code, or an ambiguity where different readings yield materially different plans —
close it before writing anything. If the investigation already answered what you
need, skip grilling; don't interrogate the user over decisions you can reasonably
make yourself.

The grilling methodology lives in dedicated skills. They're marked
`disable-model-invocation`, so you can't fire them like a normal skill — read the
one you pick and run the interview exactly as it prescribes:

- **Default — `batch-grill-me`** (`~/.claude/skills/batch-grill-me/SKILL.md`):
  asks every currently-answerable question each round, then recomputes the
  frontier as answers arrive. Resolves a broad decision set in the fewest
  round-trips; use it almost always.
- **Sequential — `grill-me`** (methodology in
  `~/.claude/skills/grilling/SKILL.md`): one question at a time, each answer
  shaping the next. Reach for it only when the decisions are so tightly dependent
  that batching would force you to guess at later questions before the earlier
  answers exist, or when the user asks to be grilled this way.

Don't start the plan while a genuine, shape-changing ambiguity is still open. The
session ends when you and the user share an understanding of what's being built.

### 4. Write `context.md`

Write `context.md` first — this is where the thinking happens.

Derive `<plan-name>` from the change: short, kebab-case, descriptive
(`feed-dedup`, `notion-store`, `auth-rate-limit`). The folder name is what makes
the plan findable later; the files inside are always `context.md` and
`path.json`, which is what lets an executor open a folder it's never seen and know
exactly where to look.

Follow the structure in **`references/templates.md`** — read it now if you
haven't; it covers both files' structure and has a worked example. The essence:

- Lead with the **problem and goal** — what's changing and why, briefly.
- Spend the bulk on the **approach and key decisions**: the changes, the
  architecture, the high-level data/control flow. Give the *why* for each
  significant decision in a sentence or two, and where you rejected a plausible
  alternative, name it and say why the chosen path won — that's the reasoning a
  reviewer most needs and most often can't reconstruct alone.
- Include **only load-bearing snippets** — a type signature that pins an
  interface, a tricky transform, a config shape. Skip boilerplate the executor
  can obviously fill in.
- Name the **affected files/areas**, the **risks or open questions**, and the
  **testing approach** at a high level.

Altitude test: a reviewer should finish knowing *what you'll do and why* — able
to challenge a specific decision, without a line-by-line script. If it reads like
source code with prose captions, it's too low; if it reads like a vague mission
statement, it's too high.

### 5. Derive `path.json`

Now decompose `context.md` into `path.json`. This is *transcription, not design*
— every step traces back to something the markdown already decided. If you find
yourself making a new decision here, stop and fix `context.md` first, then
re-derive. (When the JSON wants a step the markdown never mentioned, or the
markdown decides something the JSON doesn't reflect, that mismatch is a hole in
the plan — reconcile it in `context.md`. That tension is the feature, not a
nuisance.)

The file is a **JSON array of step objects**, each with exactly these fields:

| field    | type   | meaning |
|----------|--------|---------|
| `id`     | number | Sequential, starting at 1, in execution order. |
| `title`  | string | Short imperative label (e.g. "Add `dedupeByUrl` to the feed store"). |
| `kind`   | string | `"implementation"` — does work that changes the code/system — or `"verification"` — only checks something and changes nothing (runs tests, a linter, a build, or confirms a behavior holds). |
| `action` | string | What must be done for the step to be *complete*: which file, which function, what behavior — specific enough for an agent to execute. |
| `status` | string | Always `"pending"` on a fresh plan. |
| `notes`  | string | Extra guidance when `action` alone isn't enough — gotchas, ordering constraints, links to markdown sections. `""` when there's nothing to add. |

`kind` drives how the executor treats a step, so classify honestly:

- **Split doing from checking.** A step that both makes a change *and* verifies it
  is two steps — an `implementation` step, then a `verification` step after it.
  Only that split lets the executor treat each correctly.
- **Only verification is skippable.** At execution time a verification step may
  end up `skipped`; an implementation step never can — skipping real work would
  leave the change half-built. The validator enforces this, so don't mislabel
  load-bearing work as `verification` to make it skippable.
- **Flag expensive verifications in `notes`.** When a check is costly — a full
  suite, a long build, an external or live call — say so, so the executor knows
  to pause and ask the user before running it rather than hitting a real system
  unprompted.

A fresh plan is all `"pending"`. The other statuses — `in_progress`, `done`,
`blocked`, and `skipped` (verification only) — are outcomes the executing agent
records as it walks the plan; never write them into a fresh plan yourself.

Good steps are:

- **Exhaustive and ordered** — cover everything needed to ship the change (tests,
  migrations, wiring, cleanup — not just the interesting code), in an order where
  each step's prerequisites are already done.
- **One coherent unit each** — completable and checkable on its own. If an
  `action` needs the word "and" three times, it's probably two steps.
- **Concrete** — real files, functions, and types from your investigation.
  "Update the store" is weak; "Add a `dedupeByUrl(items)` method to
  `filesystem-feed-store.ts` that drops entries whose normalized URL already
  exists" is a step someone can act on.
- **Executable without re-reading all of `context.md`**, but free to point back to
  it in `notes` for the *why*.

Validate before you finish, and fix anything it flags (missing fields, bad
status, non-sequential ids, malformed JSON) until it passes:

```bash
python3 ~/.claude/skills/pathfinder/scripts/validate_plan.py <path-to>/<plan-name>/path.json
```

### 6. Report back

Print a short pointer, nothing more — the plan lives in the files, so don't
restate it in chat:

- The plan folder path, first — it's the single path the user hands to
  `roadrunner`.
- A one-to-two sentence summary of the chosen approach.
- The number of steps in `path.json`.
- A reminder that you haven't started implementing, and an offer to do so or to
  revise the plan.
