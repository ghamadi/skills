---
name: roadrunner
description: >-
  Executes an existing step-by-step plan — especially a pathfinder plan folder with `context.md` and `path.json` — one
  step at a time, recording each step's `status` in the file as it goes. Use whenever the user points at a plan folder
  and wants it carried out ("execute the plan", "roadrunner .claude/plans/feed-dedup", "start on the plan we just
  made"). Prefer this over ad-hoc implementation whenever there's a structured plan to follow.
---

# Roadrunner

Pathfinder finds the trail; you walk it. Carry out a plan folder exactly as written, with `path.json` as the live
record of progress.

## Open the plan

Read `context.md`, then the **whole** `path.json`, before touching step 1. The rationale tells you what each `action`
is for, and the full arc keeps an early step from painting a later one into a corner. Given only a plan name, look in
`.agents/plans/<name>/`, then `.claude/plans/<name>/`.

A part folder (`<feature>/01-<part-name>/`, beside a `design.md`) runs like any other plan: its `path.json` already
carries what the design pinned, so the design doc isn't yours to read or reconcile.

## The loop

For each step in `id` order:

1. Set its `status` to `in_progress` and save.
2. Do exactly what `action` says, heeding `notes` — no more, and no reinterpretation. A plan you "improved" mid-run is
   no longer the one the user approved.
3. When the action is genuinely complete, set `status` to `done` and save.

Save each change at once, so an interrupted run resumes from the file rather than your memory. Edit only the `status`
field, and only along `pending → in_progress → done | blocked | skipped` — the values pathfinder's validator accepts.

`action` is the source of truth; `context.md` explains the why and never overrides it. If the two disagree in a way
that changes what you'd do, that's a hole in the plan: a blocker.

## Verification steps

A `verification` step checks something and changes nothing. `done` means the check ran and held, never "I edited until
it passed"; a failed check is a blocker.

Cheap checks just run. When one will cost real time or money, or hit a live or external system — `notes` may flag it,
but judge for yourself — ask the user whether to run or skip it. `skipped` records their choice, and only a
verification can be skipped: skipping an implementation step leaves the change half-built.

## Stop, don't improvise

When a step can't be done as written — a command fails, a precondition is false, the `action` is wrong or impossible —
set it to `blocked`, tell the user briefly where you stopped and why, quoting the decisive error or finding, and stop
for direction. The user expects the plan done as agreed or halted honestly: a workaround buries a decision that was
theirs, and limping past a broken step builds confident-looking garbage on a cracked foundation.

## Confirm irreversible effects

Before a step writes to a live external system, deletes or overwrites real data, or sends something outward, confirm
with the user or route it to a sandbox, even when the plan just says "do it". Plans are written optimistically ("add
the items" when the store points at production); you're the last check before a real side effect.

## Report

When the plan is `done` or stopped at a `blocked` step: what got done, what's blocked and why, what actually changed.
The detail lives in `path.json` and the diff, so leave the plan unrestated.
