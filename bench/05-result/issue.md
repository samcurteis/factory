# Return a Result instead of throwing from parseDuration

## Goal
Callers handle invalid durations without try/catch: parseDuration and totalDuration return a Result.

## Acceptance criteria
- [ ] `parseDuration` returns `{ ok: true, value: number }` for valid input and `{ ok: false, error: ParseError }` for invalid input, and never throws (tests in `src/duration.test.ts`)
- [ ] `ParseError` is `{ input: string; kind: "empty" | "unexpected" | "unknown-unit" | "order"; message: string }`. Every invalid input in the existing tests maps to the kind that matches its current message (tests in `src/duration.test.ts`)
- [ ] `totalDuration` returns `{ ok: true, value }` with the sum, or the first input's error as `{ ok: false, error }` (tests in `src/total.test.ts`)
- [ ] `DurationError` is removed; `Result` and `ParseError` types are exported from `src/index.ts`
- [ ] Every existing valid and invalid case is still tested, against the new return shape

## How to verify
pnpm verify

## Out of scope
- Any change to which inputs are valid.

## Hints
- Current messages map to kinds: "empty" → `empty`, "unexpected" → `unexpected`, "unknown unit" → `unknown-unit`, "out of order or repeated" → `order`.
