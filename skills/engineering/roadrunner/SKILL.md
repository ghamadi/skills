---
name: roadrunner
description: >-
  Execute an existing step-by-step implementation plan — especially a pathfinder plan folder containing `context.md` and
  `path.json` — one step at a time, updating each step's `status` in the file as you go. Use whenever the user points at
  a plan folder and wants it carried out, run, executed, implemented, or "worked through": "execute the plan", "run the
  pathfinder plan", "roadrunner .claude/plans/feed-dedup", "implement this plan step by step", "start on the plan we
  just made", or right after a plan is produced and the user says to begin. The `action` fields in `path.json` are the
  source of truth; `context.md` is background only. Prefer this over ad-hoc implementation whenever there's a structured
  plan to follow and progress should be tracked.
---

# Roadrunner

Pathfinder finds the trail; you walk it. Take an existing plan folder and carry it out step by step, keeping `path.json`
itself as the live record of progress.

## Open the plan folder

The user points you at a **folder**, typically under `.claude/plans/` or `.agents/plans/`. For example:

```
.claude/plans/<plan-name>/
  context.md   ← the why: approach, decisions, architecture
  path.json    ← the what: ordered steps to execute
```

Read `context.md` first, then `path.json`. Loading the design rationale before the steps lets you execute each `action`
the way it was _meant_, and spot when a step's literal wording would miss its intent.

If you are given only a plan name without the folder, check these default locations in order:

- `.agents/plans/<plan-name>/`
- `.claude/plans/<plan-name>/`

A plan may instead be one **part** of a larger design, nested a level deeper —
`.claude/plans/<feature>/01-<part-name>/`, sibling to a `design.md`. Execute the part folder you were given and only
that one; its `path.json` already carries whatever the design pinned, so the design doc is not yours to read or
reconcile.

## The step object and its `status`

`path.json` is the executable contract: an ordered array of steps, each shaped like

```json
{ "id": 1, "title": "...", "kind": "implementation", "action": "...", "status": "pending", "notes": "..." }
```

Walk the steps in `id` order and drive each one's `status` from `pending` to `done`, doing **exactly** what `action`
says — no more.

The valid `status` values are:

- `pending`
- `in_progress`
- `done`
- `blocked`
- `skipped`

**Record progress by editing the `status` field in place.** The key is literally `status`. Don't add a new key and don't
invent values.

Untouched actions will be `pending`. Every time you pick an action, you set its status to `in_progress` before doing
anything.

Drive the `status` of each action along one of these paths:

- `pending` → `in_progress` → `done` — the normal path
- `pending` → `in_progress` → `blocked` — a step that can't be completed as written (see below)
- `pending` → `in_progress` → `skipped` — an expensive _verification_ the user chose not to run (see below)

These are the only values pathfinder's validator accepts. Persist each change to disk immediately, so an interrupted run
resumes from the file's truth rather than your memory.

The other fields tell you how to run the step; leave them unchanged:

- **`action`** — what to do. Execute it literally; don't expand or reinterpret it. A plan you "improved" mid-run is no
  longer the one the user approved.
- **`kind`** — `implementation` changes the code/system; `verification` only checks something and changes nothing (see
  below).
- **`notes`** — gotchas: ordering constraints, things to watch, pointers into `context.md`. Heed them. `context.md` is
  background for the _why_; it never overrides an `action`.

If the two files disagree in a way that changes what you should do, that's a hole in the plan — treat it as a blocker,
don't quietly pick a side.

## The loop

Read the **whole** `path.json` before touching step 1 — later steps constrain earlier ones, and knowing the full arc
keeps you from painting yourself into a corner. Then, for each step in `id` order:

1. Set `status` to `in_progress`; save.
2. Do the work in `action`.
3. When it's genuinely complete, set `status` to `done`; save.

## Verification steps are read-only

A `verification` step checks something and changes nothing. `done` means "I ran the check and it held" — never "I edited
until it passed." If the check fails, that's a blocker, not a fixup.

**For expensive verifications, ask first.** Cheap checks (a fast test, a quick lint) just run. But if a check will
clearly cost real time, money, or a hit to a live/external system — the `notes` may flag this, but use your judgment too
— pause and ask whether to run or skip it. Run → mark `done` on pass (a failed check is a blocker like any other). Skip
→ mark `skipped`, recording the user's explicit choice.

Skipping is _only_ for verifications. An `implementation` step is _never_ skipped.

## When a step won't go — stop, don't improvise

If a step can't be completed as written — a command fails, a precondition is false, the `action` is wrong or impossible
— don't engineer a workaround or soften the step until it passes. Instead: set its `status` to `blocked`, tell the user
briefly (which step, what you tried, what went wrong), and stop for direction.

The user handed you a specific plan and expects it done as agreed or halted with an honest explanation. A silent
workaround buries a decision that was theirs, and a run that limps past a broken step builds confident-looking garbage
on a cracked foundation.

## Confirm before irreversible effects

One thing plans won't say but you must do: when a step's `action` would write to a live external system, delete or
overwrite real data, or send something outward, pause and confirm — or route it to a safe sandbox — _before_ running it,
even if the plan just says "do it." Plans are written optimistically; you're the last check before a real side effect
(e.g. "add the items" when the store points at production, not a scratch file).

## Report

When the plan is fully `done` — or you've stopped at a `blocked` step — give a terse close-out: what got done, what's
left blocked and why, what actually changed. The detail already lives in `path.json` and the diffs; don't restate the
whole plan.
