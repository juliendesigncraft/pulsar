# libwebp dentro Pulsar

Serve al Convertitore per salvare in WebP: macOS lo legge ma non lo scrive (prova del 19/10/2026, `docs/2026-10-19-convertitore-prova-formati.md`). Aggiunto su richiesta esplicita dell'autore il 19/10/2026.

- Versione 1.6.0, librerie statiche per arm64, minimo macOS 26.0, copiate dalla bottiglia di Homebrew (`/opt/homebrew/Cellar/webp/1.6.0`). Pulsar gira solo da macOS 26, quindi il minimo combacia.
- Licenza BSD a tre clausole di Google (`COPYING`). Nell'app venduta il testo va tenuto: `build-vendita.sh` lo copia in `Contents/Resources/Licenze/libwebp.txt`. Va citato anche nella pagina di vendita.
- Solo tre intestazioni (encode, decode, types) e due librerie (libwebp, libsharpyuv). Il modulo Swift si chiama `CWebP` (`include/module.modulemap`), e i flag stanno in `sorgenti.sh` (`LIBRERIE`).
- Impronte SHA-256:
  - libwebp.a `60673850a52b524169cded4c4d19d0289479b07103bdd500e78f1fe1d6ffb016`
  - libsharpyuv.a `8be95e9c93d12dead02da1965e23bf0e5880e3c0e642f4abba1ff0dd3bb8478d`
- Per aggiornare: `brew upgrade webp`, poi si ricopiano gli stessi file e si aggiornano versione e impronte qui.
