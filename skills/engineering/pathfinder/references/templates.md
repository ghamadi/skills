# Templates & worked example

This file holds the full structure for both files in the plan folder (`<plan-name>/context.md` and `<plan-name>/path.json`) plus a short worked example. Read it when writing the plan.

## `context.md` structure

Use these sections as a scaffold, not a straitjacket. Drop sections that don't apply; length should scale with the size of the change. The headings below are a sensible default order. In design-driven mode most of these shrink to a pointer at `../design.md` — keep only what's specific to this part.

```markdown
# <Title> — Implementation Plan

## Problem & goal
What's changing and why, in a few sentences. What does "done" look like?
State the success criteria plainly.

## Approach
The heart of the doc. Describe the shape of the solution: the key changes,
how the pieces fit, and the architecture. Explain the *why* behind each
significant decision. Where you rejected a plausible alternative, name it and
say why the chosen path won — that's the reasoning a reviewer can't reconstruct
on their own.

## Data / control flow
(When relevant.) How data moves through the change, or the sequence of control.
A short numbered walkthrough or a small diagram often beats a paragraph.

## Key snippets
(Only the load-bearing ones.) A type signature that pins an interface, a tricky
transform, a config shape. These make a decision concrete. Skip anything the
executor can obviously fill in.

## Affected areas
The files, modules, and boundaries this touches. Helps the reader gauge blast
radius and helps the executor know where to look.

## Testing
How the change will be verified, at a high level — what kinds of tests, what
the critical cases are. Not the test code itself.

## Risks & open questions
What could go wrong, what's still uncertain, what assumptions the plan rests on.
If anything here is genuinely the user's call, it should have been raised before
writing the plan.
```

### Altitude guidance

- **Too low** (bad): the markdown reads like source code with prose captions. If the executor could copy-paste your markdown into files, you've written the implementation, not the plan.
- **Too high** (bad): "We'll improve the feed system to be more robust." No decisions, no reasoning, nothing a reviewer can push back on.
- **Right**: a reviewer finishes knowing *what you'll do and why*, could challenge a specific decision, and trusts that the details not shown are routine.

## `path.json` schema

A JSON array of step objects, each with exactly the six fields and nothing more. Field meanings, `kind` semantics, and what makes a good step are all in SKILL.md's *Derive `path.json`* section — don't re-derive them from the example below.

## Worked example (abridged)

Request: "plan the feed dedup work — we're getting the same article twice when two sources link it."

Delivered as `.claude/plans/feed-dedup/`:

**`feed-dedup/context.md`** (excerpt):

```markdown
# Feed Deduplication — Implementation Plan

## Problem & goal
The feed store appends every fetched item, so an article surfaced by two sources
appears twice. Goal: the feed never shows the same article twice, keyed by a
normalized URL. Done = adding an item whose normalized URL already exists is a
no-op, and existing duplicates are collapsed on read.

## Approach
Deduplicate at the store boundary rather than in each source adapter, so every
write path is covered by one rule and sources stay dumb. We key on a *normalized*
URL (strip tracking params, lowercase host, drop trailing slash) because raw URLs
differ across sources for the same article. Normalization lives in a pure
`normalizeUrl` util so it's testable in isolation and reusable by the read path.

Rejected: hashing title+body. It's fuzzier and more expensive, and the URL is a
reliable identity key for our sources. Not worth the complexity now.

## Key snippets
    function normalizeUrl(raw: string): string  // host lowercased, tracking
                                                 // params stripped, no trailing /

## Affected areas
- lib/utils/url.ts (new normalizeUrl)
- infrastructure/feed/feed-store/filesystem-feed-store.ts (dedup on add)
- domain/feed/services/select-novel-candidates.ts (dedup on read)

## Testing
Unit tests for normalizeUrl (param stripping, host casing, slash). Store test:
adding a dup URL is a no-op. Read test: pre-existing dups collapse to one.
```

**`feed-dedup/path.json`** (excerpt):

```json
[
  {
    "id": 1,
    "title": "Add normalizeUrl utility",
    "kind": "implementation",
    "action": "Create lib/utils/url.ts exporting normalizeUrl(raw: string): string that lowercases the host, strips known tracking params (utm_*, fbclid, gclid), and removes any trailing slash from the path.",
    "status": "pending",
    "notes": "Keep it pure — no I/O. Both the store and the read service depend on this."
  },
  {
    "id": 2,
    "title": "Write unit tests for normalizeUrl",
    "kind": "implementation",
    "action": "Add lib/utils/url.test.ts covering: tracking-param stripping, host case-insensitivity, trailing-slash removal, and a URL that needs no changes.",
    "status": "pending",
    "notes": ""
  },
  {
    "id": 3,
    "title": "Dedupe on write in the filesystem feed store",
    "kind": "implementation",
    "action": "In filesystem-feed-store.ts, before appending an item, compute normalizeUrl(item.url) and skip the append if an existing item has the same normalized URL.",
    "status": "pending",
    "notes": "See the Approach section — dedup lives at the store boundary, not in source adapters."
  },
  {
    "id": 4,
    "title": "Consolidate the accumulated diff",
    "kind": "implementation",
    "action": "Re-read every change made by steps 1-3 as one diff and run the /simplify skill over it: collapse near-duplicate helpers, share types that ended up copied, and delete scaffolding no longer reached. Change no behavior.",
    "status": "pending",
    "notes": "Both the store and the read service call normalizeUrl — check they converged on one call shape rather than two."
  },
  {
    "id": 5,
    "title": "Run the full test suite",
    "kind": "verification",
    "action": "Run the project's complete test suite and confirm it passes, including the new normalizeUrl and feed-store tests.",
    "status": "pending",
    "notes": "Expensive — the full suite spins up the integration harness and takes several minutes. The executor should check with the user before running it."
  }
]
```

Note the mix of `kind`: writing a test file is `implementation` (it changes the codebase), and so is the consolidation pass, while running the suite is `verification` (it only checks, and changes nothing). Each JSON step still traces to something the markdown already decided, and `notes` points back to the markdown for the *why* rather than re-arguing it — and, for the expensive verification, flags the cost so the executor knows to pause.
