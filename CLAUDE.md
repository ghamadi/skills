# Repo conventions

- A skill lives at `skills/<bucket>/<name>/SKILL.md`.
- Buckets group skills by what they are commonly used for.
- Eval artifacts — inputs and run output — belong at `evals/<skill>/` in the repo root, never inside a skill directory.
  Anything under a skill directory is deployment payload and travels with the skill everywhere it is installed.
- A skill copied from someone else carries their `LICENSE` file in its own directory, verbatim. That is the attribution
  — the README does not name sources individually.
