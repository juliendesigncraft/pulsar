# SwiftTerm dentro Pulsar

Serve al Terminale del notch (`Moduli/Terminale`): un terminale vero, con colori, tasti e Claude Code dentro. Aggiunto su scelta esplicita dell'autore il 07/11/2026 ("SwiftTerm dentro Pulsar").

- Versione **1.20.0** (tag del 18/08/2026, github.com/migueldeicaza/SwiftTerm). Scelta la 1.20 e non la 1.99: la 1.99 è una riscrittura uscita a ottobre e aggiornata il giorno prima dell'aggiunta.
- Licenza MIT (`LICENSE`). Nell'app venduta il testo va tenuto: `build-vendita.sh` lo copia in `Contents/Resources/Licenze/SwiftTerm.txt`. Va citato nei crediti della pagina di vendita.
- Controllo fatto prima di aggiungerla: niente rete (nessun URLSession), apre processi solo in `LocalProcess.swift` e `Pty.swift` (la shell del terminale, è il suo lavoro), i link si aprono solo al clic.
- In `Sources/` ci sono solo i file della libreria per Mac (tolti iOS, documentazione e programmi di prova). `BuildInfo.swift` sostituisce il file che SwiftPM genera da git.
- `lib/` ha la libreria già compilata, così `build.sh` non perde 80 s a ogni giro. Si rifà con `./crea.sh` (dopo un aggiornamento di Xcode, se `build.sh` dice che il modulo è stato compilato da un altro compilatore).
- Impronta di `lib/libSwiftTerm.a` al 07/11/2026: `6f544d3c4507192bade8ae413a8ebd0ac6a4eb9acf90d0e611ad37a6b7ec2c23` (cambia a ogni ricompilazione).
