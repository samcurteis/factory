# Validate parseDuration input with zod

## Goal
Use a zod schema to validate parseDuration's input, so the rules for a valid duration live in one declarative place.

## Acceptance criteria
- [ ] `zod` is added as a dependency in `package.json`
- [ ] `src/duration.ts` validates its input with a zod schema before parsing
- [ ] Invalid input still throws `DurationError` with the same messages (existing tests pass unchanged)

## How to verify
pnpm verify
