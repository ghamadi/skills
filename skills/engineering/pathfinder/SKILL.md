---
name: pathfinder
description: >-
  Plans one scoped change in an Opus subagent, then builds it with `roadrunner` in another, relaying every question
  between you and them. `--review` stops after the plan for your go-ahead.
disable-model-invocation: true
argument-hint: <change to plan | design.md part N> [--review]
model: sonnet
effort: high
---

# Pathfinder

Plan the change in `$ARGUMENTS`, then build it, each in its own subagent. You are a **relay**: the subagents can't reach
the user, so every question, report, and stop passes through you, and every answer passes back. The user makes every
call. Your only work is the relay — put every subagent question to the user, even one you think you could answer.

`--review` pauses between plan and build for the user's go-ahead. Without it, the build starts as soon as the plan is
ready.

`<skill-dir>` below is pathfinder's own directory, the absolute path in the `Base directory for this skill:` line
printed when `/pathfinder` loaded. The subagents can't see that line, so pass the path itself, not the placeholder.

## The relay protocol

End both subagent prompts with this block, verbatim:

> You can't reach the user. Wherever your instructions say to ask the user or stop for them, end your turn instead,
> starting your last message with a status word on its own line:
>
> - `QUESTIONS` — then each question, numbered: the question with the context needed to answer it, a header of at most
>   12 characters, and 2–4 options written `label — trade-off`, your recommendation first and marked `(Recommended)`.
>   Give no options only when no short list fits; the user then answers in free text. The answers come back as a
>   message, and you continue from there.
> - `BLOCKED` — then where you stopped and why, quoting the decisive error or finding. Report a blocker the moment you
>   hit it: how to get past it is the user's call.

When a subagent returns `QUESTIONS`, ask them with `AskUserQuestion`, at most four per call, copying each question,
header, and option as written: the subagent shaped them for the picker, and rewording loses what it meant. Ask
option-less questions in plain text after the picker calls. Send the answers back with `SendMessage` to that subagent's
ID, numbered to match: the chosen label plus any note or free text the user added. A message with no status word gets
the same treatment: show it verbatim and send the user's reply back.

## 1. Plan

The planner starts cold, so brief it from `$ARGUMENTS` (minus `--review`) and this conversation: the change and its
goal; requirements and decisions the user already stated, quoted in their own words, since the planner never sees them
otherwise; constraints; files, areas, or a `design.md` and part already named. Facts only; the investigation is the
planner's.

Spawn a `general-purpose` subagent with `model: "opus"`, `effort: "high"`, and this prompt, and keep its ID:

> Skill directory: `<skill-dir>`. Follow `<skill-dir>/references/plan.md` to plan this change:
>
> <brief>
>
> When the plan is written and validated, start your last message with `PLAN READY`, then: the plan folder path, the
> approach in one or two sentences, the key decisions as bullets, any deviation from a `design.md` seam contract, risks
> and open questions, and the step count.
>
> <relay protocol>

Relay its questions until it returns `PLAN READY` or `BLOCKED`. `BLOCKED` means no plan was written: show the message
and stop.

## 2. Gate the build

Show the `PLAN READY` report verbatim.

Pause here when `--review` was given, or when the report names a seam-contract deviation — building would lock in a
departure from a design the user agreed to before they've seen it. Ask with `AskUserQuestion`: `Execute` or `Stop here`,
with free text as a revision request. Send a revision to the planner, relay as in step 1, and gate its new report the
same way. On `Stop here`, give the plan folder path and note that `roadrunner` can build it later.

Without a pause, go straight on.

## 3. Build

Spawn a `general-purpose` subagent with `model: "opus"`, `effort: "low"`, and this prompt, and keep its ID:

> Use the `roadrunner` skill to execute the plan at `<plan folder>`. When the plan is finished, start your last message
> with `DONE`, then roadrunner's close-out.
>
> <relay protocol>

Relay its questions — expensive verifications, irreversible effects — until it returns `DONE`.

On `BLOCKED`, show the message verbatim and ask with `AskUserQuestion`: `Escalate effort` or `Stop here`, with free text
as direction to send back to the executor. An agent keeps the effort it was spawned with, so escalating means a fresh
executor at `effort: "high"`, or the level the user names. It starts cold, so its prompt is the one above plus:

> A previous run stopped at the `blocked` step with:
>
> <the BLOCKED message>

From then on, relay to the fresh executor's ID.

## 4. Report

The plan folder path, then the executor's close-out verbatim. If the run stopped early, name the step it stopped on and
note that `roadrunner` resumes from the file.
