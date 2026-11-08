# Pulsar for Windows (beta)

A notch for Windows 11, built with Claude.

**[Download the source and build file (ZIP)](https://github.com/juliendesigncraft/pulsar/releases/download/windows-beta-1/Pulsar-for-Windows-beta.zip)**

## What it does

A small black island at the top centre of your screen.

- Hover it and it opens: music, a shelf for your files, a terminal, and a dev tab with your Git branch, dev servers by port and your Claude Code limit.
- Touch the left edge of the screen, just under the notch: a dial for volume and a timer.
- Touch the right edge: a side menu that follows Claude Code live. See every step, every file it changed, and approve its commands from any app.

## Build it (nothing to install)

1. Unzip the folder anywhere.
2. Double-click `build.bat`. It uses the C# compiler that Windows already has.
3. Open `Desktop\Pulsar\Pulsar.exe`.

The icon near the clock has the menu: Connect Claude Code, Start with Windows, Quit. To see the side menu without Claude Code, choose "Run a demo session".

## Claude Code

"Connect Claude Code" adds a status line and hooks to `~/.claude/settings.json`. It makes a dated copy of that file first, and leaves an existing status line alone. To undo it, restore that copy.

## What is tested and what is not

This is a beta. It was tested in a Windows 11 ARM virtual machine with no audio and no internet.

- **Seen working:** the notch, opening on hover, the file shelf, the terminal, the dev tab, the timer, and the side menu with the demo session.
- **Not tested yet:** music and volume on a PC with audio, real Claude Code on Windows, Ctrl+Alt+T, and general speed on a real PC.

If something breaks, the icon menu has "Open log".

## Privacy

Pulsar stays on your PC. It sends nothing anywhere. Its data is in `%APPDATA%\Pulsar`.

Your Windows may show its own warnings for an app you compiled yourself. The code is all in `src`: read it, change it, ask Claude to make it yours.

Free for personal, non-commercial use: see [LICENSE](LICENSE).
