# Add formatDuration, the inverse of parseDuration

## Goal
Callers can turn a number of seconds back into the short text form that parseDuration reads.

## Acceptance criteria
- [ ] `formatDuration(5400)` returns `"1h30m"` (test in `src/format.test.ts`)
- [ ] `formatDuration(45)` returns `"45s"` (test in `src/format.test.ts`)
- [ ] `formatDuration(3723)` returns `"1h2m3s"` (test in `src/format.test.ts`)
- [ ] Round trip: for any whole number of seconds `n >= 0`, `parseDuration(formatDuration(n)) === n` (test in `src/format.test.ts`)
- [ ] Exported from `src/index.ts`

## How to verify
pnpm verify

## Out of scope
- Negative or fractional seconds: callers never pass them.
- Days or larger units.

## Hints
- Put it in a new file `src/format.ts`.
