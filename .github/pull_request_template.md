## What does this pull request change?

<!-- Describe the player-visible result and scope. For new behavior, state its
entry point and defaults; for a bug, give reproduction and expected vs actual
behavior. Do not leave an irrelevant bug-reproduction section for a new feature. -->

## Existing mechanisms and affected consumers

<!-- Name the existing owner/contract being extended, its affected consumers and
any new hook/worker/storage requirement. Explain why reuse was not sufficient
if a new mechanism is necessary. Link the technical document you updated. -->

## How was the change verified?

<!-- Give exact commands/results, relevant host/dependency/environment settings
and why the selected existing tests cover dependent assumptions. Follow AGENTS
and docs/TESTING.md: do not run the whole runner without authorization. -->

## Player interaction and remaining gaps

<!-- For changed UI, summarize open → select/edit → confirm/cancel → return,
defaults/focus, ordered speech (including duplicates) and cues. Distinguish model
tests, native controls with captured speech, live accounts, physical keys and
actual listening. For a docs/data-only change say why UI checks do not apply.
List failures, skips, timeouts and unverified paths; do not mark them passed. -->

## Completion checklist

- [ ] New behavior/regressions and dependent existing tests were updated together;
      the selected checks above were run after the final relevant edit.
- [ ] Existing shared mechanisms, affected contexts and lifetime/cost were reviewed.
- [ ] Help, owning documentation, translations and generated outputs were updated
      where affected; inapplicable items are explained above.
- [ ] For questions/rules, the mandatory editorial template was read in full and
      applied, sources checked and every changed text reviewed separately for
      natural target-language wording; or this PR changes neither.
- [ ] No profiles, private logs/reports, tokens, keys, certificates or `.eltsetup`
      packages are included. No unrequested version/build or server changes.

<!-- Local results are not GitHub Actions results. Do not claim remote CI passed
until the run for this commit has actually completed successfully. -->
