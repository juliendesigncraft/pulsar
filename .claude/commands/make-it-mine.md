---
description: Guided tour to customize Pulsar with Claude, one change at a time
---

Help me make Pulsar my own. Read `CLAUDE.md` first.

1. Ask me three short questions, one at a time: what I use most on my Mac, what I would remove from Pulsar, and one thing I wish the notch did.
2. From my answers, propose at most three changes, each in one line, smallest first. Wait for me to pick.
3. Make the change I pick, following the design and safety rules in `CLAUDE.md`. Add new files to `sorgenti.sh`.
4. Run `./build.sh`. If it fails, fix it. When it builds, tell me to quit Pulsar and run `open build/Pulsar.app`, and what to look at.
5. Ask if I want the next change.

Keep explanations short and plain: I may not be a developer.
