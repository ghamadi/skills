# Report template

Fill in this structure exactly. Order findings by severity, then ledger order.

## Severity

- **high**: harms on a normal path (bug, security hole, data loss, introduced check failure, merge conflict).
- **medium**: harms under specific conditions (edge case, rollout hazard, risky untested path, maintainability damage).
- **low**: real but contained (rough UX state, low-risk untested path).

## Template

```markdown
> **⚠ Checks incomplete: <checks> could not run.** <reason>. Fix <reason> and rerun.

## Summary

<intent, one or two sentences> (from context | inferred)

Reviewed `<branch>` (`<sha>`[ + uncommitted changes]) against `<base>` (`<sha>`).

Checks: `<command>` passed · `<command>` failed (<n> introduced, <n> pre-existing) · `<command>` could not run ·
<check> not found · `<command>` wrote to <paths | unknown paths> ·
merge with base: <clean | conflicts in <files> | could not check>[ (committed changes only)]. Logs: `<run_dir>/logs`

Ledger: <n> entries closed · <n> changed contracts, <n> consumers checked · excluded: <file> (+<n>/−<n>), …

## Findings

### 1. <title> · <severity>[ · unverified][ · may be pre-existing]

**Where:** <file:line for every site>
**Issue:** <what is wrong>
**Impact:** <what breaks, for whom>
**Action:** <the specific change>
**Assumption:** <unverified findings only>

## Findings Summary

|  id | severity            | title   | where                     |
| --: | ------------------- | ------- | ------------------------- |
|   1 | <severity[ · flag]> | <title> | <main site>[ (+<n> more)] |
```

- The banner appears only when a check could not run.
- With no findings, Findings says "No findings." and the table is omitted.
