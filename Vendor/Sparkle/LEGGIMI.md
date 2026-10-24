# Sparkle dentro Pulsar

Serve agli aggiornamenti automatici della build di vendita 3.0 (fase 5, compito 3b). Deciso dall'autore il 21/10/2026 ("Serve tutto. Importante."), scaricato il 24/10/2026 con la sua autorizzazione a prendere il codice utile per Pulsar. La build personale (`-D PERSONALE`) non lo collega e non lo importa.

## Da dove viene

- Versione **2.10.0**, l'ultima stabile al 24/10/2026, pubblicata il 13/09/2026 (più di cinque settimane prima). Le uscite dopo il 13/09 sono solo una beta precedente (2.10.0-beta.1): nessuna stabile più nuova.
- Fonte: solo la pagina ufficiale delle release, https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0, file `Sparkle-2.10.0.tar.xz` (16 319 840 byte), caricato dall'account `Sparkle-Bot` del progetto.
- Somma di controllo SHA-256 dell'archivio: `c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c`. Calcolata sul file scaricato e confrontata con quella pubblicata da GitHub per lo stesso file (campo `digest` della release): uguali.
- Il progetto non pubblica una firma Apple: `Sparkle.framework` ha la firma ad hoc (`codesign --verify --deep --strict` valida). Nell'app la rifirma `build-vendita.sh` con l'identità di Pulsar.
- Architetture: universale (arm64 e x86_64). Minimo macOS 12, Pulsar chiede macOS 26.

## Licenza

MIT (Andy Matuschak, Elgato, Kornel Lesiński, Mayur Pawashe e altri), più le licenze delle parti esterne nello stesso file: bsdiff (BSD a due clausole), sais-lite (MIT), ed25519 di Orson Peters (zlib), SUSignatureVerifier (BSD). Testo completo in `LICENSE`. Si può vendere un'app che lo contiene: basta tenere il testo. `build-vendita.sh` lo copia in `Contents/Resources/Licenze/Sparkle.txt`. Va citato anche nella pagina di vendita.

## Cosa c'è qui (solo ciò che serve)

- `Sparkle.framework`: intero com'era nell'archivio (le intestazioni servono per compilare, le parti interne all'app). Dentro: `Autoupdate` (sostituisce l'app quando si accetta un aggiornamento), `Updater.app` (la finestrella di avanzamento), `XPCServices/Downloader.xpc` e `Installer.xpc` (usati solo dalle app sandbox: Pulsar non lo è e non le accende).
- `bin/generate_keys`: crea la coppia di chiavi EdDSA e mette la privata nel Portachiavi. **Lo lancia l'autore**, una volta (CREA-PRODOTTI.md).
- `bin/sign_update`: firma lo zip di un aggiornamento con la chiave privata del Portachiavi. Lo lancia `pubblica-aggiornamento.sh`, cioè l'autore.
- `LICENSE`.
- Lasciati fuori: `generate_appcast`, `BinaryDelta`, l'app di prova, i simboli di debug, gli script DSA vecchi.

Impronte SHA-256:
- `Sparkle.framework/Versions/B/Sparkle` `a4b35bf38c12044686d0910dcb680560f1ff000061fbe19541c0b5e41c6c6008`
- `bin/generate_keys` `c37679f98d9121981cf7b2d18592fdc8b44931bffa604acf10c9e11791b6222e`
- `bin/sign_update` `43c249771bafc3aa581228abae00731a012d324691b8292860896635050be76b`

## Cosa fa in rete

Solo due cose, e solo nella build di vendita:
1. legge l'appcast, `https://juliendesigncraft.vercel.app/pulsar/appcast.xml` (`SUFeedURL` nell'Info.plist): una volta al giorno se "Cerca aggiornamenti da solo" è acceso (pagina Generale, acceso di serie), oppure quando si sceglie "Check for Updates…" nel menu;
2. se c'è una versione nuova e la si accetta, scarica il suo zip dall'indirizzo scritto nell'appcast.

Nessun profilo del sistema (`SUEnableSystemProfiling` non c'è, quindi spento), niente statistiche. La richiesta porta il solito User-Agent con nome e versione dell'app. Prima di installare Sparkle controlla la firma EdDSA dello zip con la chiave pubblica nell'Info.plist (`SUPublicEDKey`) e che la firma di codice della nuova app sia valida: uno zip cambiato per strada viene rifiutato.

## Cosa installa

Niente di suo nel sistema: nessun LaunchAgent, nessun elemento di login, nessun servizio. Lo zip scaricato va nella cache dell'app (`~/Library/Caches/com.juliendesigncraft.pulsar/`); quando si accetta, `Autoupdate` sostituisce Pulsar.app e la riapre.

## Per aggiornare Sparkle

Scaricare la nuova stabile solo dalla pagina delle release, confrontare la somma, rileggere CHANGELOG e LICENSE, ricopiare gli stessi file e aggiornare qui versione, data e impronte.
