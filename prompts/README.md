# Pulsar, the prompt

> Part of [juliendesigncraft/pulsar](https://github.com/juliendesigncraft/pulsar): the app and its prompts live in one repo. The prompts are under CC BY-NC 4.0 ([LICENSE](LICENSE)), the code under PolyForm Noncommercial.

Pulsar is the app that lives in my Mac's menu bar and around the notch. I built all of it with Claude Code. This folder is the whole thing as prompts: one folder per part, each with the prompt I would give Claude Code today, the reference images, and the problems that cost me days, so they don't cost you the same.

It's free. If you use Claude Code, you can build your own Pulsar and change anything.

## The parts

| Part | What it does | Folder |
|---|---|---|
| Lite | A clean menu bar, your desktop in a menu, a sound for every key, the small system switches | [`lite/`](lite) |
| Agent | Claude Code live in the notch and in a panel on the edge: every step, permissions from any app, diffs | [`agent/`](agent) |
| Mixer | Two dials on the left edge: volume with a mixer for each app and a timer, screen and keyboard light | [`mixer/`](mixer) |
| Island | The notch as a Dynamic Island: music with live lyrics, tiles, peeks for battery and apps, Claude's questions | [`island/`](island) |
| Stow | Drop a file on the notch and it changes form; your Desktop and Downloads tidied with your own rules | [`stow/`](stow) |
| Rowline | Every window side by side in one row that scrolls, with a thin slider at the bottom | [`rowline/`](rowline) |
| Themes | Dark Matte and White Matte: one switch changes Pulsar, macOS, the wallpaper and the folder icons | [`themes/`](themes) |

Each part works on its own. If you want them together, start with Lite and tell Claude to add every next part to the same app.

## How to use a prompt

1. Open the folder of the part you want and download the images in `images/`.
2. Copy the prompt and paste it into Claude Code, on a Mac, with the images attached.
3. Build it step by step: Claude shows you a plan first and waits for your OK. After every step it builds the app and tells you how to try it.

It won't come out identical to mine on the first try. Mine is the result of weeks of small fixes. You'll get a working first version in a session or two: then use it every day and ask Claude for one detail at a time.

## What you need

- A Mac with Apple silicon and macOS 14 or later (the per-app mixer needs 14.4).
- Claude Code with your own Claude plan.
- Apple's Command Line Tools (swiftc). No Xcode project needed.

## Want it ready to use, with updates?

Pulsar is on Gumroad, one app with a license key for the paid parts:

- [Pulsar Lite](https://juliendesigncraft.gumroad.com/l/pulsar-lite): free, with 7 days of everything.
- [Pulsar Agent](https://juliendesigncraft.gumroad.com/l/pulsar-agent): $7.
- [Pulsar Mixer](https://juliendesigncraft.gumroad.com/l/pulsar-mixer): $5.
- [Pulsar Complete](https://juliendesigncraft.gumroad.com/l/pulsar-complete): $15, everything.

## License

The prompts and images in this repo are under [CC BY-NC 4.0](LICENSE): use them, change them and share them, with credit to @juliendesigncraft, for anything except commercial use. The Rowline code has its own license in its repo.

Made by [@juliendesigncraft](https://instagram.com/juliendesigncraft) with Claude.
