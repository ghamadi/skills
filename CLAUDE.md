# Repo conventions

- A skill lives at `skills/<bucket>/<name>/SKILL.md`.
- There are two buckets. `engineering/` is daily code work; `sessions/` is for
  skills that act on the working session itself — the conversation rather than
  any one subject — and so apply whatever the topic is. Pick by that rule, not
  by whim.
- Eval artifacts — inputs and run output — belong at `evals/<skill>/` in the
  repo root, never inside a skill directory. Anything under a skill directory is
  deployment payload and travels with the skill everywhere it is installed.
- Every skill is listed in `README.md`, grouped by bucket, with an "invoked by"
  column (you vs model) that matches its `disable-model-invocation` frontmatter.
- A skill copied from someone else carries their `LICENSE` file in its own
  directory, verbatim. That is the attribution — the README does not name
  sources individually.
