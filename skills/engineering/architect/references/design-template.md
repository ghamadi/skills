# `design.md` structure & worked example

## Structure

Sections are a scaffold, not a straitjacket — drop what doesn't apply, and let length scale with the work.

```markdown
# <Feature> — Design

## Problem & goal

What's being built and why, in a few sentences. What does "done" look like for the whole feature? State the success
criteria plainly.

## Architecture

The heart of the document: the shape of the solution, how the pieces fit, and why. Give the reasoning behind each
significant decision. Where you rejected a plausible alternative, name it and say why the chosen path won — that's what
a reviewer can't reconstruct alone, and what stops a part planner from quietly re-deciding it.

## Seam contracts

Everything two or more parts share, pinned by name: module paths, exported signatures, type and table names, event
names, config keys. Shape only, per the altitude rule in SKILL.md.

## Parts

Ordered. For each:

### N. <part name>

One sentence saying what it does — no "and".

- **Delivers:** what exists after this part that didn't before.
- **Assumes:** what it takes for granted (already in the codebase, or delivered by an earlier part — name which).
- **Touches:** the files and modules it's expected to change.

## Risks & open questions

What could go wrong, what's still uncertain, what the design rests on. Anything genuinely the user's call should already
have been settled while grilling.
```

## Worked example (abridged)

Request: "we want patients to log whether they took each care-plan task, see a streak, and get a nudge when they miss
one."

Delivered as `.claude/plans/adherence-logging/design.md`:

```markdown
# Adherence Logging — Design

## Problem & goal

Care plans list what a patient should do but record nothing about whether they did it. Goal: a patient can mark a task
done for a given day, see a per-task streak, and receive a nudge after a miss. Done = adherence events persist, the plan
view shows streaks, and a missed scheduled task produces a nudge within the day.

## Architecture

Adherence is stored as an append-only `adherence_event` log keyed by (task, local date), not as a mutable `completed`
flag on the task. Tasks recur, so a flag has nowhere to put yesterday; an event log makes streaks a pure fold over
history and keeps late corrections auditable — which matters because this is medication data.

Streaks are computed on read rather than maintained as a counter. A counter has to be repaired whenever an event arrives
out of order, which timezone-shifted clients will do. The fold is O(days) over a bounded window and needs no repair.

Nudges are driven by a scheduled sweep that diffs expected occurrences against logged events. Rejected: emitting a nudge
job at log time — it inverts the trigger (nothing is logged, so nothing fires) and can't detect the absence we care
about.

## Seam contracts

- `lib/domain/adherence/entities/adherence-event.ts`
  `type AdherenceEvent = { taskId: string; localDate: string; status: 'done' | 'skipped'; recordedAt: Date }`
  `localDate` is `YYYY-MM-DD` in the patient's timezone — every part resolves the date the same way, via
  `resolveLocalDate(at, tz)` in `lib/utils/time.ts`.
- `lib/domain/adherence/repository.ts` — `AdherenceRepository` with `append(event)`, `listForTask(taskId, since)`. Part
  1 defines and implements it; parts 2 and 3 consume it and add no query paths of their own.
- Table `adherence_events`, unique on `(task_id, local_date)`, last write wins.
- `computeStreak(events, asOf): number` in `lib/domain/adherence/services/compute-streak.ts` — part 2 owns it, part 3
  reads it for nudge copy.

## Parts

### 1. Persist adherence events

Store and read adherence events behind a repository.

- **Delivers:** the `adherence_events` table and migration, `AdherenceEvent`, `AdherenceRepository` and its Postgres
  implementation, `resolveLocalDate`.
- **Assumes:** nothing beyond the existing care-plan schema.
- **Touches:** `lib/domain/adherence/**` (new), `lib/utils/time.ts`, migrations.

### 2. Log and display adherence in the plan view

Let a patient mark a task for a day and see its streak.

- **Delivers:** the log mutation, `computeStreak`, streak display on the task row.
- **Assumes:** part 1's repository and `AdherenceEvent`.
- **Touches:** `components/care-plans/**`, `lib/domain/adherence/services/**`.

### 3. Nudge on a missed task

Sweep for expected-but-unlogged occurrences and send a nudge.

- **Delivers:** the sweep job, miss detection built on `listForTask`, nudge dispatch.
- **Assumes:** parts 1 and 2 — the event log and `computeStreak`.
- **Touches:** `lib/jobs/**`, the existing notification sender.

## Risks & open questions

- Timezone changes mid-streak can produce two events for one local day; the unique constraint collapses them, last write
  wins.
- The sweep's cost grows with active plans × tasks. Fine at current scale; revisit if plan count outgrows a single
  nightly pass.
```

Note what the seam contracts pin and what they don't: `AdherenceEvent`'s shape, the repository's methods, the table's
uniqueness rule, and `computeStreak`'s signature are all named, because parts 2 and 3 are built by agents that will
never see part 1's plan. How the Postgres implementation batches its writes, or which component renders the streak
badge, is left open — that's interior, each part planner's call.
