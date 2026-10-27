# Planning one change

Turn one scoped change into a **plan folder**:

```
<plan-name>/
  context.md   ← the why: approach, key decisions, architecture, data/control flow
  path.json    ← the what: exhaustive, ordered steps derived from context.md
```

`context.md` is for whoever judges _whether the approach is right_; `path.json` is for whoever _executes_ it. The
executor is a separate agent that sees only this folder — not the conversation, not your investigation — so the folder
is the whole handoff. Your work ends at the validated folder; building is the executor's.

`<skill-dir>` below is the skill directory your prompt names.

## Two modes

- **Standalone** — no design doc. You investigate, settle the approach with the user, and `context.md` is where the
  design happens.
- **Design-driven** — you're pointed at a `design.md` from `architect` and a part of it. The architecture is settled;
  you plan _one part_ faithfully, not redesign it.

With a `design.md`, read it in full before anything else. Its **Seam contracts** section is binding: every path,
signature, and name it pins is a fact your plan builds on. Sibling parts are built against those same contracts by
agents that never see your plan.

## 1. Investigate

A plan is a _diff against reality_; a plan built on guesses is worse than none, because it looks authoritative while
being wrong. Read the modules, functions, data structures, and boundaries the change touches. Follow the grain of how
this codebase already does similar things. Find the seams: the interfaces, call sites, and tests that will have to move.
Scale this to the change — a one-file tweak needs a glance, a cross-cutting refactor a real survey.

## 2. Check the scope

Test what you found: **could half the change be dropped and still leave something worth shipping?** If so, it's two
changes wearing one name — link expiry and a viewer audit trail are each valuable alone. Layers don't count: a column,
the DTO field that carries it, and the component that renders it are one change when they serve one purpose. Second
test: does the change introduce a module boundary that later, separate work will build on?

If either answer is yes, ask once whether to run `architect` first or plan it anyway, and honor the answer — the user
often knows the work is big and wants the plan regardless. It's worth asking because a plan spanning a whole ticket
invents an architecture _and_ decomposes it in one pass; the architecture gets the thinner half of the attention, and
the result is a long run of faithful steps with no spine. If the user picks `architect`, write nothing and report that
as your blocker.

In design-driven mode, don't ask. A part that fails the first test is a hole in the design, which step 4 covers; the
second test doesn't apply, because the design already placed the boundaries.

## 3. Resolve the destination

**Standalone:** `.claude/plans/<plan-name>/` at the project root (the git root, or the top-most directory containing the
project). `<plan-name>` is short, kebab-case, descriptive (`feed-dedup`, `auth-rate-limit`).

**Design-driven:** nest beside the design, so the feature travels as one unit and the parts stay ordered on disk:

```
.claude/plans/<feature>/
  design.md
  01-<part-name>/{context.md, path.json}
  02-<part-name>/{context.md, path.json}
```

`NN` matches the part's position in the design's sequence.

The folder holds exactly `context.md` and `path.json`, so an executor opening it cold knows where to look. If the user
names another location, honor it and carry the convention across: the plan folder still nests inside, and a part keeps
its `NN-` prefix. If the plan folder already exists, it may be a prior plan, possibly part-executed: ask whether to
replace it or pick another name.

## 4. Grill the user on what's still open

Close every load-bearing unknown before writing anything: a missing constraint or success criterion ("add caching" —
cache _what_, invalidated _how_, bounded by _what_?), two goals that can't both hold, a request that conflicts with the
code, or an ambiguity whose readings yield materially different plans. Skip what the investigation already answered and
the calls you can reasonably make yourself.

Run the interview by reading one of these and following it exactly:

- **Default — `<skill-dir>/../batch-grill-me/SKILL.md`**: every currently-answerable question each round, the frontier
  recomputed as answers arrive. Fewest round-trips for a broad decision set.
- **Sequential — `<skill-dir>/../grilling/SKILL.md`**: one question at a time, each answer shaping the next. Only when
  the decisions are so tightly dependent that batching would force guesses, or the user asks for it.

**In design-driven mode, keep this to a minimum.** The load-bearing decisions were settled with the user when the design
was written; re-opening them is how a part drifts off the spine. Ask only about something interior to this part that the
design left open.

**When the design has a gap or contradicts the code**, leave `design.md` as it is — it's the spine every sibling part
builds against, and the agent with the narrowest view is the wrong one to move it. What you do turns on whether this
part can still be planned:

- **Blocking** — a contract this part needs was never pinned, or the part is really two. Write nothing; report the gap
  as your blocker.
- **Non-blocking** — the gap lands in a different part, or a pinned contract is unimplementable as literally written but
  an obvious small deviation preserves its _purpose_ (the codebase injects dependencies through constructors, so a
  pinned free function becomes a method of the same name and signature at the same path). Plan the part, take the
  smallest such deviation, record it in `context.md`, and name it in your report.

Most are non-blocking: block only when planning would mean guessing at something the design was supposed to decide.

## 5. Write `context.md`

Read **`<skill-dir>/references/example.md`** first: a worked plan folder showing both files at the right altitude.

Title it `# <Title> — Implementation Plan`, then use these sections in this order, dropping any that don't apply. Length
scales with the change.

- **Problem & goal** — what's changing and why, in a few sentences, and what "done" looks like.
- **Approach** — the bulk of the doc: the key changes, how the pieces fit, the architecture. Give the _why_ for each
  significant decision in a sentence or two. Where you rejected a plausible alternative, name it and say why the chosen
  path won — the reasoning a reviewer most needs and can least reconstruct alone.
- **Data / control flow** — how data moves through the change, or the sequence of control. A short numbered walkthrough
  or small diagram beats a paragraph.
- **Key snippets** — only load-bearing ones: a type signature that pins an interface, a tricky transform, a config
  shape.
- **Affected areas** — the files, modules, and boundaries touched: the blast radius, and where the executor should look.
- **Testing** — how the change is verified: the kinds of tests and the critical cases, not test code.
- **Risks & open questions** — what could go wrong, what's uncertain, what the plan assumes. Anything that's the user's
  call should have been asked in step 4, not parked here.

Altitude test: a reviewer finishes knowing _what you'll do and why_, can challenge a specific decision, and trusts that
the details not shown are routine. Too low: source code with prose captions — if the executor could paste your markdown
into files, you've written the implementation. Too high: "we'll make the feed system more robust" — no decision a
reviewer can push back on.

**In design-driven mode, point at `../design.md` rather than restating it.** Keep only what's true of _this part_ that
the design didn't say — your interior decisions, the files you found, this part's testing. A restated architecture is a
second copy that can silently disagree with the first.

## 6. Derive `path.json`

Decompose `context.md` into steps. This is _transcription, not design_: every step traces to something the markdown
already decided. When the JSON wants a step the markdown never mentioned, or the markdown decides something no step
reflects, that's a hole in the plan — fix `context.md` first, then re-derive.

The file is a JSON array of step objects, each with exactly these fields:

| field    | type   | meaning                                                                                                                                                           |
| -------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`     | number | Sequential from 1, in execution order.                                                                                                                            |
| `title`  | string | Short imperative label (e.g. "Add `dedupeByUrl` to the feed store").                                                                                              |
| `kind`   | string | `"implementation"` changes the code/system; `"verification"` only checks something — runs tests, a linter, a build, or confirms a behavior — and changes nothing. |
| `action` | string | What must be done for the step to be _complete_: which file, which function, what behavior.                                                                       |
| `status` | string | Always `"pending"`; the executor records the rest as it goes.                                                                                                     |
| `notes`  | string | What `action` alone doesn't carry — gotchas, ordering constraints, pointers into `context.md`. `""` when there's nothing to add.                                  |

`kind` drives how the executor treats a step, so classify honestly:

- **Split doing from checking.** A step that both makes a change and verifies it is two steps: `implementation`, then
  `verification`.
- **Only verification is skippable.** The executor may skip a verification at the user's word but never an
  implementation step, so real work labeled `verification` can be skipped and leave the change half-built.
- **Flag expensive verifications in `notes`** — a full suite, a long build, an external or live call — so the executor
  asks the user before running it.

Good steps are:

- **Exhaustive and ordered** — everything needed to ship (tests, migrations, wiring, cleanup — not just the interesting
  code), each step's prerequisites already done.
- **One coherent unit each** — if half an `action` could be done and checked without the other half, it's two steps.
- **Concrete** — real files, functions, and types from your investigation. "Update the store" is weak; "Add a
  `dedupeByUrl(items)` method to `filesystem-feed-store.ts` that drops entries whose normalized URL already exists" is a
  step someone can act on.
- **Executable without re-reading all of `context.md`**, pointing back to it in `notes` for the _why_.

**Close with a consolidation pass.** The executor does exactly what each step says and no more, so over a dozen steps
the code accretes: near-duplicate helpers, a type that should have been shared, scaffolding from step 3 that step 9 made
dead. End with an `implementation` step that re-reads the plan's accumulated diff and consolidates it — the `/simplify`
skill is built for this — followed by the verification steps that prove nothing broke. Bound it to the plan's own diff:
pre-existing duplication nearby is a change the user hasn't asked for.

Validate, and fix whatever it flags until it passes:

```bash
python3 <skill-dir>/scripts/validate_plan.py <plan-folder>/path.json
```
