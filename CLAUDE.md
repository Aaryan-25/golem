# Rules for Claude in this repo

The owner (lilgolemwitch) can't read code. He steers by plain-language explanations and by testing on his laptop.

0. **Read MAP.md** to find your way around the code (what each file does, where things live, how to change safely).
1. **Read PLAN.md first.** Only work on the step marked NOW. Don't start later steps "while you're at it".
2. **Ask before any long coding session, and before any installer build.** First say in plain words what will change and why, then wait for a yes.
3. **Keep each change small.** If a change needs more than about 300 lines, split it and ask.
4. **New ideas go to IDEAS.md**, not into code. That includes ideas he mentions in passing.
5. **Owner's choice (21 Nov 2026):** build Steps 5 to 8 (up to a working Control Panel) before he tests on the laptop.
   To make up for it, every step gets an automated test on GitHub in a virtual laptop, and each step stays a
   separate, plain-words change. Steps 2 to 8 then get tested on the laptop together, using TESTS.md.
5b. **Owner's choice (22 Nov 2026):** build Steps A to E (the shadow realm look) one after another; he tests the
   final version. Same rules: each step a separate plain-words change with a GitHub test.
6. **A step is done only when he reports that its "done when" test passed on the laptop.** Then mark it done in PLAN.md and move NOW to the next step.
7. **Follow DECISIONS.md.** If something there seems wrong, ask. Don't quietly change it.
8. **Don't copy code from `Aaryan-25/shilp` in bulk.** Use it as a reference, and bring over only what the current step needs.
9. **Explain in plain words** what was made and how he tests it.
