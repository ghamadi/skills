#!/usr/bin/env python3
"""Validate a plan folder's path.json.

Checks that the file is a JSON array of step objects, each with the required
fields and correct types, ids sequential from 1, a valid `kind`, and
status == "pending" on a fresh plan. Also enforces that only verification steps
may be "skipped". Exits non-zero and prints every problem it finds.

Usage:
    python3 validate_plan.py path/to/<plan-name>/path.json
"""
import json
import sys

REQUIRED = {"id", "title", "kind", "action", "status", "notes"}
ALLOWED_STATUS = {"pending", "in_progress", "done", "blocked", "skipped"}
ALLOWED_KIND = {"implementation", "verification"}


def validate(path):
    errors = []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        return [f"file not found: {path}"]
    except json.JSONDecodeError as e:
        return [f"invalid JSON: {e}"]

    if not isinstance(data, list):
        return ["top-level value must be a JSON array of step objects"]
    if not data:
        return ["plan is empty — a plan needs at least one step"]

    for i, step in enumerate(data):
        where = f"step[{i}]"
        if not isinstance(step, dict):
            errors.append(f"{where}: must be an object")
            continue

        missing = REQUIRED - step.keys()
        if missing:
            errors.append(f"{where}: missing field(s): {', '.join(sorted(missing))}")
        extra = step.keys() - REQUIRED
        if extra:
            errors.append(f"{where}: unexpected field(s): {', '.join(sorted(extra))}")

        if "id" in step:
            if not isinstance(step["id"], int) or isinstance(step["id"], bool):
                errors.append(f"{where}: id must be a number, got {step['id']!r}")
            elif step["id"] != i + 1:
                errors.append(f"{where}: id should be {i + 1} (sequential), got {step['id']!r}")

        for field in ("title", "action"):
            if field in step:
                if not isinstance(step[field], str):
                    errors.append(f"{where}: {field} must be a string")
                elif not step[field].strip():
                    errors.append(f"{where}: {field} must be non-empty")

        if "notes" in step and not isinstance(step["notes"], str):
            errors.append(f"{where}: notes must be a string (use \"\" when empty)")

        if "kind" in step and step["kind"] not in ALLOWED_KIND:
            errors.append(
                f"{where}: kind {step['kind']!r} not in {sorted(ALLOWED_KIND)}"
            )

        if "status" in step:
            if step["status"] not in ALLOWED_STATUS:
                errors.append(
                    f"{where}: status {step['status']!r} not in {sorted(ALLOWED_STATUS)}"
                )
            elif step["status"] != "pending":
                # Fresh plans should be all-pending; warn but don't hard-fail on
                # a recognized status, since a plan may be re-validated mid-run.
                errors.append(
                    f"{where}: status is {step['status']!r}; a fresh plan should be \"pending\""
                )

        # An implementation step must never be skipped — skipping is only a
        # choice for verification. This holds at any point in a plan's life,
        # so it's a hard error regardless of how far the run has progressed.
        if step.get("status") == "skipped" and step.get("kind") == "implementation":
            errors.append(
                f"{where}: an implementation step can never be skipped — "
                "only verification steps may be skipped"
            )

    return errors


def main():
    if len(sys.argv) != 2:
        print("usage: python3 validate_plan.py path/to/<plan-name>/path.json", file=sys.stderr)
        sys.exit(2)

    errors = validate(sys.argv[1])
    if errors:
        print(f"✗ {len(errors)} problem(s) found:")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)

    print("✓ plan is valid")


if __name__ == "__main__":
    main()
