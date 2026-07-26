# skills

These are the agent skills I use day to day with Claude Code. They encode
my own workflow and preferences rather than aiming to be a library for
general use. If something here fits your needs, feel free to borrow it;
that's exactly why the repo is public.

Some skills are my own, and some are copied from public sources such as the
magnificent [mattpocock/skills](https://github.com/mattpocock/skills) repo.
The [License](#license) section below covers how sources are credited.

## Layout

Skills live at `skills/<bucket>/<name>/SKILL.md`; the two buckets are the
groups in the reference below. Development artifacts for a skill (eval
inputs and run output) live under `evals/<skill>/` at the repo root, never
inside the skill directory — everything inside a skill directory is
deployment payload and travels with the skill wherever it's installed.

## Skills Reference

In the tables, "you" means the skill sets `disable-model-invocation: true`
and only runs when you type `/<name>`; "model" means the model picks it up
whenever the skill's description matches the task.

### `engineering/` — daily software engineering work

| skill                                                | invoked by | what it does                                                                                            |
| ---------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| [pathfinder](skills/engineering/pathfinder/SKILL.md) | model      | Produces a self-contained plan folder: a `context.md` design doc and step-by-step `path.json`.          |
| [roadrunner](skills/engineering/roadrunner/SKILL.md) | model      | Executes a pathfinder plan one step at a time, updating each step's `status` in `path.json` as it goes. |

### `sessions/` — skills useful within any given session

| skill                                                     | invoked by | what it does                                                                              |
| --------------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------- |
| [grilling](skills/sessions/grilling/SKILL.md)             | model      | Interviews you relentlessly about a plan, decision, or idea to stress-test your thinking. |
| [grill-me](skills/sessions/grill-me/SKILL.md)             | you        | An explicit trigger for `grilling` — the same interview, one question at a time.          |
| [batch-grill-me](skills/sessions/batch-grill-me/SKILL.md) | you        | The `grilling` interview run in rounds: every currently answerable question at once.      |

## License

[MIT](LICENSE).

Some skills here originate elsewhere and are included under their original
terms. Where a skill directory contains its own `LICENSE` file, that file
governs the contents of that directory and names the original author.
Everything else is my own work.
