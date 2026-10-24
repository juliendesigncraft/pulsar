# Fonti dei suoni

## alpaca/ e gli altri pacchetti meccanici
alpaca, blackink, redink, mxblack, mxbrown, holypanda, cream, turquoise, topre, bluealps, boxnavy, buckling:
dal progetto ClickClack di César Ferreira e contributori.
https://github.com/cesarferreira/clickclack (assets/switchtypes/alpaca)
Licenza MIT, testo completo in `LICENSE-clickclack.txt`. Convertiti da mp3 a wav 48 kHz e livellati con `livella.py` (un solo guadagno per pacchetto). Alpaca scaricato il 01/10/2026, gli altri 11 lo stesso giorno. Cherry MX Blue escluso: nel repository è incompleto.

## typewriter/
Macchina da scrivere Hermes Precisa 305, registrazioni di BigSoundBank (Joseph Sardin).
Licenza CC0, pubblico dominio: https://bigsoundbank.com
- `key_single.wav` ← sound 2842 "Typewriter, Key"
- `space.wav` ← sound 2843 "Typewriter, space"
- `bell_4.wav`, `bell_5.wav` ← sound 2844, 2845 "Typewriter, Bell"
- `key_00..11.wav` ← colpi singoli ritagliati da 2835, 2836, 2839 (battitura lenta)
- `enter.wav` ← un colpo pesante di 2835 rinforzato con una copia un'ottava sotto.
  Le registrazioni non contengono un ritorno carrello vero: questo è un sostituto.
Scaricati il 01/10/2026.

## mouse/
Clic del mouse sintetizzati in codice il 01/10/2026 (rumore filtrato + risonanza + corpo basso), nessuna registrazione esterna. Tre varianti di pressione (`down_0..2`) e di rilascio (`up_0..2`).

## goccia/
Goccia d'acqua sintetizzata in codice l'11/10/2026 con `goccia.py` (seno con glissando verso l'alto, coda esponenziale, una seconda bollicina e un corpo basso), nessuna registrazione esterna. Tre varianti `drop_0..2`, suonano quando un elemento si stacca da un bordo. Non passano dalla saturazione dei tasti: il livello è già nel file.
