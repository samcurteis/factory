# Allow spaces between parts in parseDuration

## Goal
People often type a space between parts, like `1h 30m`. That should parse the same as `1h30m`.

## Acceptance criteria
- [ ] `parseDuration("1h 30m")` returns `5400` (test case in `src/duration.test.ts`)
- [ ] `parseDuration("1h  30m  15s")` returns `5415` (test case in `src/duration.test.ts`)
- [ ] All existing tests still pass

## How to verify
pnpm verify
