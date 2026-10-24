# Pulsar: map for Claude

You are helping someone change Pulsar, a macOS menu bar and notch app written in Swift (AppKit + SwiftUI), no Xcode project. Read this first, then the files it points to. Code comments are in Italian: read them, they explain the why. Write new comments in the user's language.

## Build and check
- Build: `./build.sh` (needs macOS 26, Apple silicon, Command Line Tools). Output: `build/Pulsar.app`.
- Source builds pass `-D DA_SORGENTE`: everything is unlocked, no license network calls, Sparkle stays off.
- The file list lives in `sorgenti.sh` (`CORE`, `MODULI`, `ROWLINE_KIT`). **A new .swift file compiles only if you add it there.**
- After every change, run `./build.sh` and fix errors before saying you are done. Tell the user to quit the running Pulsar and `open build/Pulsar.app`.

## Where things are
| You want to change | Look in |
|---|---|
| Colors, the two themes (Dark Matte, White Matte) | `Core/Tema.swift`: `Volta` is the island scale (`a2` is the accent blue), `Night` the older panels |
| A saved setting (UserDefaults) | `Core/Impostazioni.swift`, `enum Chiave`: add a case, read with `Impostazioni` helpers |
| UI text | `T("italiano", "english")` from `Core/Strumenti.swift`: always give both |
| The island tiles | protocol `IslandWidget` in `Moduli/Widget/widget.swift`; list of available tiles in `Moduli/Isola/isola.swift` (`model.widgets = [...]`); default layout `TileLayout.standard` in `Moduli/Isola/isola-logica.swift` |
| Tile size | one cell is 84 pt wide, 8 pt gap, 96 pt tall, corner radius 20; tiles take 1 to 3 cells |
| A whole module (on/off, permissions) | protocol `ModuloPulsar` and `Registro` in `Core/Moduli.swift`; each module conforms in its own folder |
| Claude Code in the notch | `Moduli/Agent/` (panel, line, window), hook in `agente/hook.py`, connection in `Core/CollegaClaude.swift` |
| The menu bar menu and app start | `Moduli/Lite/main.swift` |
| Settings window pages | `Moduli/Lite/Impostazioni/Pagina*.swift`, building blocks in `MattoniImpostazioni.swift` |
| Volume dial and mixer | `Moduli/Mixer/ghiera.swift` |
| Music | `Moduli/Media/` |
| File conversion (Stow) | `Moduli/Convertitore/` (logic in `convertitore-logica.swift`, kept pure and testable) |
| Window row (Rowline) | `Moduli/Rowline/` (its `Kit/` compiles as a separate static library, see `sorgenti.sh`) |
| Voice | `Moduli/Anima/` |
| Keyboard sounds | `sounds/<pack>/`, loaded by the Lite module |
| Where Pulsar keeps its data | `Cartelle.dati` in `Core/Cartelle.swift`: `~/Library/Application Support/<bundle id>` |

## How to add a tile (the most common request)
1. Create `Moduli/Widget/widget-<name>.swift` with a struct conforming to `IslandWidget` (`id`, `title`, `symbol` = an SF Symbol name, `body(cells:)`). Copy the shape of `MusicWidget` or `WeatherWidget` in `widget.swift`.
2. Add it to `model.widgets` in `Moduli/Isola/isola.swift`.
3. Add the file to `MODULI` in `sorgenti.sh`.
4. Build. The user adds the tile from the island's edit mode (the + button).

## Design rules (keep the app coherent)
- Two themes only, Dark Matte and White Matte: read colors from `Volta`/`Theme`, never hard-code new ones.
- One typeface: the system font (SF). Light or regular weights, no bold titles.
- No outlines around elements, no drop shadows on text. Shapes are rounded; hierarchy comes from size and gray, not from boxes.
- The island opens under the menu bar and never covers it.
- Short labels. If something needs a paragraph to explain, it needs a simpler design.

## Safety rules
- Ask before adding a dependency, a network call, or a new macOS permission. Pulsar asks for permissions only when a feature needs them; keep it that way.
- Never write to the user's files outside Pulsar's data folder without showing what will change first (see how `CollegaClaude.swift` previews and backs up `~/.claude/settings.json`).
- Don't remove the hook's fallback: if Pulsar is closed, Claude Code must keep working in the terminal.
- The license (`LICENSE`) forbids selling Pulsar or versions of it. If the user asks to prepare a paid release, say so.
