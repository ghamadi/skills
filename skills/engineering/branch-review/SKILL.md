---
name: branch-review
description: Pre-merge review of a branch against a base ref, reporting only issues that need action before merge.
argument-hint: --base <ref> [context]
disable-model-invocation: true
---

Review a branch against its base and report every issue the branch _introduces_ that needs action before merge. Never
edit the code under review: read, grep, and run checks.

Scripts live in `scripts/` beside this file; run them by absolute path from inside the repository. A script that prints
`status: error` has failed: reply with its error and how to fix it, then stop.

## Arguments

- `--base <ref>` (required): the ref to review against, used exactly as it exists locally. Fetching is the user's job.
  When it is missing, stop and ask: "Did you mean `--base <ref>`?" if the arguments open with something ref-like,
  otherwise "Base ref? (e.g. `origin/main`)".
- Any other text is **context**: the change's intent, divergence from existing patterns that is intentional, issues
  known to exist on the base, paths to treat as generated. Context overrides anything you would infer.

## Steps

### 1. Setup

Run `setup.sh --base <ref>`. The review covers the checked-out branch, uncommitted and untracked changes included.

- `status: empty`: reply "Nothing to review: `<branch>` has no changes against `<base>`." and stop.
- `status: ok`: every later command and file read happens inside `repo_root`.

Done when setup prints `status: ok`.

### 2. Inventory

Run `inventory.sh <run_dir> [<glob> ...]`, passing context's generated paths as globs. It prints changed files with
numbered hunks (H1, H2, …), excluded files, merge conflicts with the base, and files changed on both sides. It runs
before the checks so that nothing a check writes is counted as the branch's change.

Done when inventory prints `status: ok`.

### 3. Checks

Find the commands that type-check (or compile), lint, and test the project. Take each from the first source that
defines it: repository instructions (`CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README`), task definitions
(`package.json` scripts, `Makefile`, `justfile`, or commands the language's toolchain ships with, such as `go vet` or
`cargo test`), then the CI pipeline for pull requests. Add a separate format check only when CI blocks merges on it;
scope to affected packages only when CI does. Take only commands that verify code, in a form that writes nothing: drop
any `--fix` or `--write` the project's command carries. A check no source defines is "not found", even when the code
hints at a tool for it.

Run checks one at a time, each in its own `run-checks.sh <run_dir> '<command>'` call with a long timeout. Run one that
may take more than 10 minutes in the background, and wait for it before starting the next. Read a log of 150 lines or
fewer whole; in a longer one, search for the runner's failure markers with surrounding lines, plus its closing summary.

A check that prints `modified:` wrote to the tree. Keep what it wrote, shown by the command on that line, out of the
review. `modified: unknown` means the tree could not be snapshotted, so the check may have written anything.

Classify every failure:

- **could not run**: the environment blocked it (missing env var, service, network, tool, or dependency), not the code.
- **introduced**: its location or error chain touches a file or symbol the branch changed, or the branch changed the
  tool's configuration.
- **pre-existing**: it touches nothing the branch changed, or context declares it.
- Unclear: report it as a finding marked `may be pre-existing`.

Done when every check has a status and every failure has a class.

### 4. Ledger

From the inventory, write the _ledger_ to `<run_dir>/ledger.md`, one line per entry. An entry is the smallest named
unit holding changed lines: function, method, component, handler, query, schema, migration, config key; the whole file
when it has no smaller unit.

```
E3 | src/billing/refund.ts | refundOrder() | H1,H2 | contract: return type | consumers: api/refunds.ts, jobs/retry.ts | tests: refund.test.ts | lenses: correctness,errors,data,tests
```

- **contract**: what callers or readers can observe changing (signature, return shape, behavior, schema, event, route,
  config key), or `none`.
- **consumers**: for every contract change, its users, found with `git grep -n --untracked`.
- **tests**: the tests that exercise the unit, found by grepping its name, route, or component; or `none`.
- **lenses**: the [lenses](#lenses) that apply. `correctness` and `tests` apply to every code entry.

Done when `reconcile.sh <run_dir>` reports no problem other than `open:` entries.

### 5. Review

Take entries in ledger order. For each, read its hunks with `git diff-index -p -M <merge_base> -- <file>`, naming both
paths for a rename, or read the whole file when untracked. Unlike `git diff`, this ignores the user's diff settings,
so the hunks match the inventory's. Read the code around them that the unit depends on, check every consumer, and
apply every lens. Record candidate findings as you go, then append `closed E<n> <lenses applied>` to the ledger. For
each file changed on both sides, and each file in `<run_dir>/base-changed.txt` that an entry imports from, read the
base's change (`git diff-tree -p <merge_base> <base> -- <file>`) against the branch's use of it.

Done when `reconcile.sh <run_dir>` prints `status: reconciled`.

### 6. Verify

Settle every candidate against the code: read the call path, or run an existing test that exercises it.

- Confirmed: keep.
- Refuted: drop.
- Unresolved: keep, marked `unverified`, with the assumption it rests on.

Group what survives by root cause: one finding per cause, listing every site. Done when every candidate is confirmed,
refuted, or unverified.

### 7. Report

Read `report-template.md` beside this file and fill it in. Done when the report follows the template.

## What counts as a finding

A finding is _introduced_: this branch added the risk. A path the branch adds is introduced even inside a file that was
already untested or messy. Anything the branch does not touch is pre-existing and stays out of Findings.

It carries real risk under at least one [lens](#lenses), and it is tied to specific code with a clear fix. Praise,
informational notes, nitpicks, formatting, and style preferences are not findings.

Always findings:

- Every introduced check failure, with the command and the decisive error lines.
- Every merge conflict with the base.
- An invariant the code documents or trusts callers to keep (bounds, ordering, uniqueness, non-null) where silent
  violation is plausible and a guard would make the failure explicit.
- Implementation incomplete against the intent, from context or inferred.
- A new or changed path no test exercises, when a silent break there carries real risk. In security, authz,
  permissions, payments, or data-integrity code, flag it however simple the path looks: simplicity is not evidence of
  safety. Pure presentation, copy, and logic-free config need no test.

Divergence that context declares intentional is not a consistency finding; bugs the divergence causes still are.

State each claim as fact or as an explicit assumption.

## Lenses

- **correctness**: logic, regressions, edge cases, invariants, type holes with runtime impact, completeness.
- **errors**: failure handling, partial failure, feedback when something fails.
- **security**: authn/authz, injection, secrets, privacy.
- **data**: integrity, effect on existing data, concurrent writes.
- **perf**: practical cost such as N+1 queries, unbounded work, oversized payloads.
- **consistency**: existing conventions and nearby implementations; bypassed boundaries, duplicated important logic,
  mixed responsibilities, weakened contracts.
- **ux**: user flows with broken, confusing, inaccessible, or incomplete states.
- **deploy**: migrations, backwards compatibility, stale clients, partial failure, mixed old/new versions, rollback.
- **tests**: whether a test exercises each new or changed path.
