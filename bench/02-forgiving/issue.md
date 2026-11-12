# Make parseDuration more forgiving

## Goal
People write durations in all sorts of ways. parseDuration should accept the common ones instead of throwing.

## Acceptance criteria
- [ ] Common ways of writing a duration are accepted
- [ ] Existing valid inputs still parse the same

## How to verify
pnpm verify
