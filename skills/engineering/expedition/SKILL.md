---
name: expedition
description: >-
  Plans every part of an `architect` design in parallel — one `pathfinder` subagent per part, each writing its plan
  folder beside `design.md`. Orchestrates only: writes no plan, code, or design edit itself.
disable-model-invocation: true
argument-hint: <design-folder> [part numbers]
model: sonnet
effort: high
---

# Expedition

Spawn one subagent per part of the design in `$ARGUMENTS`, all in parallel, each running the `pathfinder` skill. You only orchestrate — never
touch code, `design.md`, or the plans.

1. **Read the Parts section of `design.md`.** Nothing else — the planners investigate the code. Plan only the parts the
   user named, if any. Each part's folder is `NN-<kebab-part-name>/` beside `design.md`; if one already exists, ask
   whether to replace or skip it before spawning anything.

2. **Spawn all planners in one message**, each with `model: "opus"` and this prompt:

   > Use the `pathfinder` skill to plan part N ("<part name>") of `<folder>/design.md`. Write the plan to
   > `<folder>/NN-<kebab-part-name>/`.
   >
   > Parts before N may not be built yet. Treat what they deliver, as the design pins it, as already in the codebase —
   > its absence from the code is expected, not a design/code disagreement.
   >
   > You can't reach the user. Where pathfinder would ask, make the call and record it as an open question in
   > `context.md`. If the design blocks this part, write nothing.
   >
   > Reply in five lines or fewer: the plan folder and step count, or the blocker; plus any deviation from a seam
   > contract, or "no deviations".

3. **Report** when all return: one line per part (folder and step count, or blocker), then every seam deviation. Flag
   deviations prominently — sibling parts were planned against the original contract, so one part's deviation can break
   another's plan.
