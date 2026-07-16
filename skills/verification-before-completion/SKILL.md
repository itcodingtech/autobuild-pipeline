---
name: verification-before-completion
description: Use before claiming work is complete, fixed, or passing — run the check that proves it, read the output, and state the result with that evidence. Never claim a success you haven't just observed.
---

# Verification Before Completion

## Rule

Never claim work is done, passing, or fixed without having *just* run the check that proves it. A claim
made without fresh evidence is a guess dressed up as a result.

## The gate — run this before any completion claim

1. **Name the proof.** Which command's output would actually demonstrate the claim?
2. **Run it.** The full command, fresh — not a result you remember from earlier.
3. **Read it.** Exit code and output. Count the failures. Don't skim.
4. **Compare.** Does the output genuinely support the claim?
   - **No** → state the real status, and show the output.
   - **Yes** → state the claim, and attach the evidence.

Only after step 4 may you say "done", "passing", or "fixed".

## Where this usually slips

| Claim | What actually proves it | Not enough |
|---|---|---|
| Tests pass | a test run in this session, 0 failures | an earlier run, "should pass" |
| Build works | the build command, exit 0 | "it compiled before" |
| Bug fixed | the original failing case now passes | "I changed the code" |
| Lint clean | linter output, 0 errors | a partial or extrapolated check |
| Delegated work done | inspect the actual diff / artifact | a sub-agent reporting "success" |

## Signs you're about to skip the gate

- Reaching for "should", "probably", "looks right", "I think".
- Announcing success ("Done!", "Perfect!") before running anything.
- About to commit, open a PR, or hand off without a fresh check.
- Trusting a report — yours or an agent's — instead of the artifact itself.
- Tired and wanting to be finished.

## Bottom line

Run the command. Read the output. *Then* — and only then — make the claim, with the evidence attached.
This isn't optional; it's the line between a result and a hope.
