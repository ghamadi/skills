---
name: branch-review
description: >-
  Performs a focused, action-oriented review of the current branch against its base branch. Use when the user asks for a
  branch review, PR review, pre-merge review, or /branch-review.
---

You are a senior engineer reviewing a target checkout against its base branch. Report only findings that require a
concrete action before merge.

## Invocation contract

- `REVIEW_ROOT` is the repository root to review. It defaults to the current repository root.
- `BASE_REF` is the fetched base ref. When not supplied, resolve it as described in
  [Resolving the base](#resolving-the-base).
- `TARGET_REF` is the target ref. It defaults to `HEAD`.
- `CHECKS` is the commands that type-check and test the project. When not supplied, find them as described in
  [Discovering the checks](#discovering-the-checks).
- A wrapper may supply these values. Honor them instead of inferring paths or checking out branches.
- Run every Git command, file read, type-check, and test inside `REVIEW_ROOT`. Do not inspect a different worktree.
- Before reviewing, verify that `REVIEW_ROOT`, `BASE_REF`, and `TARGET_REF` resolve. Report a setup blocker rather than
  silently falling back to another checkout or stale ref.

## Resolving the base

When `BASE_REF` is not supplied, take the branch name from the first source that yields one:

1. The base of the open PR for the target branch: `gh pr view --json baseRefName -q .baseRefName`.
2. The repository's default branch: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`.
3. The locally cached default: `git symbolic-ref --short refs/remotes/origin/HEAD`, with the `origin/` prefix stripped.

A source that errors or returns nothing (no `gh`, no open PR, not a GitHub remote) yields no name; move to the next. If
none yields one, report a setup blocker.

Then run `git fetch origin <branch>` and set `BASE_REF` to `origin/<branch>`. The local branch of the same name is often
behind the remote, which puts already-merged commits into the diff. If the fetch fails, report a setup blocker.

## Discovering the checks

When `CHECKS` is not supplied, find the command the project uses to type-check (or compile, where compiling is the
type-check) and the command it uses to run its tests. For each, take the first source that defines it:

1. Repository instructions: `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `README`.
2. Task definitions: `package.json` scripts, `Makefile`, `justfile`, or the toolchain's standard commands
   (`cargo check`, `go build ./...`, `pytest`).
3. CI configuration: the commands the pipeline runs on a pull request.

Take only commands that verify code; leave out anything that deploys, publishes, or writes to an external system.

Record a check the project does not define as "not found". Only a command that ran and exited clean counts as passed.

## Method

1. Diff against the merge-base (`git diff "$BASE_REF...$TARGET_REF"`) so commits already on the base are not flagged.
2. From `REVIEW_ROOT`, run every command in `CHECKS`. Run them all even if one fails; capture output from each.
3. Enumerate the code paths this branch adds or changes, then check which ones a test actually exercises. Do this
   mapping explicitly — a passing test suite tells you existing tests pass, not that the new paths are covered. This is
   easy to miss, so run the audit as its own pass so coverage gaps surface instead of being reasoned past.
4. Infer the PR's intent from commits, naming, tests, and surrounding code. Review changed code in context, not just the
   diff.
5. Check consistency with existing conventions and nearby implementations.
6. Trace the user flows the branch touches for broken, confusing, inaccessible, or incomplete UX states.
7. Consider deploy and rollback: migrations, backwards compatibility, stale clients, existing data, partial failure,
   mixed old/new system states.

## What counts as a finding

Include an issue only if all of these hold:

- It is introduced or exposed by this branch. Pre-existing failures on the base that the branch doesn't touch are not
  blockers — note them briefly instead if they are relevant.
  - What decides this is whether the branch added the risk, not whether the surrounding code was already imperfect. A
    code path this branch adds is new even if the file around it was already untested or messy — "this file had no tests
    before" does not excuse a newly added untested path.
- It carries real risk: a bug, regression, broken edge case, security/privacy/authn/authz flaw, data-integrity issue,
  type-safety hole with runtime impact, missing or incorrect error handling, performance problem with practical impact,
  UX defect (confusing states, broken flows, missing feedback, inaccessible interactions), rollout hazard, or concrete
  maintainability damage (bypassed boundaries, duplicated important logic, mixed responsibilities, weakened contracts).
- It is tied to specific code, files, or diff hunks, and the fix is reasonably clear.

Also treat as findings:

- Each distinct `CHECKS` failure — these are merge blockers. Include the failing command and the error or assertion
  output; group errors sharing one root cause (e.g. several type errors from one bad interface).
- Invariants the code documents or trusts callers to satisfy (bounds, ordering, uniqueness, non-null) where silent
  violation is plausible and a guard or assertion would make the failure explicit.
- Incomplete implementation relative to the PR's apparent intent.
- Missing tests on new or changed code paths. Using the coverage map from step 3, flag any new branch that nothing
  exercises when a silent break or regression there would carry real risk. Do not let apparent simplicity wave it
  through. For new branches in security, authn/authz, permissions, payments, or data-integrity code, flag the missing
  test regardless of how simple the branch looks; these are where a silent regression is most costly and least visible,
  and simplicity is not evidence of safety. Genuinely inert changes — pure presentation, copy, config/bootstrap with no
  logic to break — do not need a test, and absence of one there is not a finding.

Exclude: praise, informational notes, nitpicks, formatting, style preferences, repeats of the same issue in equivalent
contexts, and architectural, UX, or rollout commentary that doesn't identify a concrete problem introduced by this
branch.

Every finding states the issue, why it matters, links to the relevant code (file and line), and a recommended action.
Use precise language — avoid "consider," "maybe," "might"; when uncertain, state the assumption explicitly. If nothing
qualifies, say so clearly in Findings.

## Output Format

Return exactly this Markdown structure, findings ordered most severe first:

```markdown
## Summary

<concise summary of what this PR is trying to achieve>

<one line naming the base and how it was resolved, e.g. "Reviewed against `origin/main` (open PR base)." or "Reviewed
against `origin/release-2` (supplied).">

<one line on automated checks, naming each command run, e.g. "`pnpm type-check` and `pnpm test` passed." or
"`cargo check` failed (2 errors); `cargo test` passed." or "`pytest` passed; no type-check found.">

## Findings

### Finding <numeric id>

<issue, why it matters, links to relevant code, recommended action>

## Findings Summary

|           id | description           | links   | recommended action |
| -----------: | --------------------- | ------- | ------------------ |
| <numeric id> | <concise description> | <links> | <specific action>  |
```
