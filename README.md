# skills

These are the agent skills I use day to day with Claude Code. They encode my own workflow and preferences rather than
aiming to be a library for general use. If something here fits your needs, feel free to grab it.

Some skills are my own, and some are copied from public sources such as
[mattpocock/skills](https://github.com/mattpocock/skills) repo. The [License](#license) section below covers how sources
are credited.

## Layout

Skills live at `skills/<bucket>/<name>/SKILL.md`, in two buckets:

- `engineering/` — daily software engineering work.
- `sessions/` — skills that act on the working session itself rather than any one subject, so they are useful within any
  given session.

Development artifacts for a skill (eval inputs and run output) live under `evals/<skill>/` at the repo root, never
inside the skill directory — everything inside a skill directory is deployment payload and travels with the skill
wherever it's installed.

## License

[MIT](LICENSE).

Some skills here originate elsewhere and are included under their original terms. Where a skill directory contains its
own `LICENSE` file, that file governs the contents of that directory and names the original author. Everything else is
my own.
