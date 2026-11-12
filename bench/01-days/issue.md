# Support days (d) in parseDuration

## Goal
Durations of a day or more can be written with a `d` unit, e.g. `2d` or `1d12h`.

## Acceptance criteria
- [ ] `parseDuration("1d")` returns `86400` (test case in `src/duration.test.ts`)
- [ ] `parseDuration("1d12h30m")` returns `131400` (test case in `src/duration.test.ts`)
- [ ] `d` comes before `h` like the other units: `parseDuration("12h1d")` throws `DurationError` (test case in `src/duration.test.ts`)
- [ ] All existing tests still pass unchanged

## How to verify
pnpm verify

## Out of scope
- Weeks or any other new unit.
- Changing `totalDuration`.
