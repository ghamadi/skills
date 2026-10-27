# Worked example

Request: "plan the feed dedup work — we're getting the same article twice when two sources link it."

Delivered as `.claude/plans/feed-dedup/`.

**`context.md`** (excerpt):

```markdown
# Feed Deduplication — Implementation Plan

## Problem & goal

The feed store appends every fetched item, so an article surfaced by two sources appears twice. Goal: the feed never
shows the same article twice, keyed by a normalized URL. Done = adding an item whose normalized URL already exists is a
no-op, and existing duplicates are collapsed on read.

## Approach

Deduplicate at the store boundary rather than in each source adapter, so every write path is covered by one rule and
sources stay dumb. We key on a _normalized_ URL (strip tracking params, lowercase host, drop trailing slash) because raw
URLs differ across sources for the same article. Normalization lives in a pure `normalizeUrl` util so it's testable in
isolation and reusable by the read path.

Rejected: hashing title+body. It's fuzzier and more expensive, and the URL is a reliable identity key for our sources.
Not worth the complexity now.

## Key snippets

    function normalizeUrl(raw: string): string  // host lowercased, tracking
                                                 // params stripped, no trailing /

## Affected areas

- lib/utils/url.ts (new normalizeUrl)
- infrastructure/feed/feed-store/filesystem-feed-store.ts (dedup on add)
- domain/feed/services/select-novel-candidates.ts (dedup on read)

## Testing

Unit tests for normalizeUrl (param stripping, host casing, slash). Store test: adding a dup URL is a no-op. Read test:
pre-existing dups collapse to one.
```

**`path.json`** (excerpt — steps 4–6, the store test and the read-path dedup with its test, are omitted):

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
    "id": 7,
    "title": "Consolidate the accumulated diff",
    "kind": "implementation",
    "action": "Re-read every change made by steps 1-6 as one diff and run the /simplify skill over it: collapse near-duplicate helpers, share types that ended up copied, and delete scaffolding no longer reached. Change no behavior.",
    "status": "pending",
    "notes": "Both the store and the read service call normalizeUrl — check they converged on one call shape rather than two."
  },
  {
    "id": 8,
    "title": "Run the full test suite",
    "kind": "verification",
    "action": "Run the project's complete test suite and confirm it passes, including the new normalizeUrl, feed-store, and read-path tests.",
    "status": "pending",
    "notes": "Expensive — the full suite spins up the integration harness and takes several minutes. The executor should check with the user before running it."
  }
]
```

Note the mix of `kind`: writing a test file is `implementation` (it changes the codebase), and so is the consolidation
pass, while running the suite is `verification` (it only checks, and changes nothing). Each JSON step traces to
something the markdown already decided, and `notes` points back to the markdown for the _why_ rather than re-arguing it
— and, for the expensive verification, flags the cost so the executor knows to pause.
