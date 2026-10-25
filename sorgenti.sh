# Lista unica dei sorgenti di Pulsar, letta con `source` da build.sh, build-vendita.sh e compila.sh.
# Array zsh, percorsi relativi alla cartella di Pulsar. main.swift sta per primo in MODULI.
# CORE = il nucleo comune, MODULI = tutto il resto dell'app.
CORE=(Core/Impostazioni.swift Core/Persona.swift Core/Cartelle.swift Core/Licenza.swift Core/Moduli.swift Core/LicenzaViva.swift Core/Tema.swift Core/Pannelli.swift Core/Strumenti.swift
  Core/Bordi.swift Core/Sfondo.swift Core/Leggera.swift Core/Razzo.swift
  Core/PermessiPannelli.swift Core/Permessi.swift Core/CollegaClaude.swift Core/Scorciatoie.swift Core/BenvenutoLogica.swift Core/Riunione.swift)

MODULI=(
  Moduli/Lite/main.swift Moduli/Agent/agente.swift Moduli/Agent/agente-linea.swift Moduli/Agent/agente-finestra.swift
  Moduli/Isola/isola-nuova.swift Moduli/Isola/isola-email.swift Moduli/Media/musica-viva.swift Moduli/Mixer/ghiera.swift
  Moduli/Isola/isola-logica.swift Moduli/Isola/isola.swift Moduli/Media/media.swift Moduli/Widget/widget.swift Moduli/Media/browser.swift
  Moduli/Media/miniatura.swift Moduli/Isola/isola-agente.swift Moduli/Isola/isola-sistema.swift Moduli/Isola/riunione-isola.swift Moduli/Widget/widget-extra.swift Moduli/Griglia/griglia.swift
  Moduli/Temi/temi.swift Moduli/Temi/temi-scrivania-logica.swift Moduli/Temi/temi-scrivania.swift Moduli/Anima/anima.swift Moduli/Anima/anima-cose.swift Moduli/Anima/anima-stella.swift Moduli/Widget/widget-hitodama.swift
  Moduli/Lite/nothing.swift Moduli/Lite/barra-guardia.swift Moduli/Media/musica-led.swift Moduli/Widget/widget-braun.swift
  Moduli/Lite/Impostazioni/MattoniImpostazioni.swift Moduli/Lite/Impostazioni/FinestraImpostazioni.swift Moduli/Lite/Impostazioni/PaginaGenerale.swift
  Moduli/Lite/Impostazioni/PaginaPermessi.swift Moduli/Lite/Impostazioni/PaginaLicenza.swift Moduli/Lite/Impostazioni/PaginaScorciatoie.swift
  Moduli/Lite/Impostazioni/PaginaInfo.swift Moduli/Lite/Impostazioni/PaginaBarra.swift Moduli/Lite/Impostazioni/PaginaSuoni.swift
  Moduli/Lite/Impostazioni/FotoImpostazioni.swift Moduli/Lite/Impostazioni/Benvenuto.swift
  Moduli/Lite/Impostazioni/PaginaAgent.swift Moduli/Lite/Impostazioni/PaginaMixer.swift Moduli/Lite/Impostazioni/PaginaIsola.swift
  Moduli/Lite/Impostazioni/PaginaVoce.swift Moduli/Lite/Impostazioni/PaginaAspetto.swift
  # Muta (19/10): converte e mette a posto. Blocco a parte, così le pagine nuove sopra non lo urtano.
  Moduli/Convertitore/convertitore-logica.swift Moduli/Convertitore/convertitore-motore.swift Moduli/Convertitore/riordino-logica.swift
  Moduli/Convertitore/muta-zona.swift Moduli/Convertitore/muta.swift Moduli/Convertitore/muta-viste.swift Moduli/Convertitore/strumenti-logica.swift
  Moduli/Lite/Impostazioni/PaginaMuta.swift Moduli/Lite/Impostazioni/PaginaRowline.swift
  # Lanciatori (24/10, nella Lite): la lista si cambia dalla pagina delle Impostazioni; nella build dell'autore la dà Spazio (Personale/lanciatori-personale.swift)
  Moduli/Lanciatori/lanciatori-lista.swift Moduli/Lanciatori/lanciatori.swift Moduli/Lite/Impostazioni/PaginaLanciatori.swift
)


# Librerie esterne (solo libwebp, per il Convertitore: Vendor/libwebp/LEGGIMI.md). Vanno passate a ogni swiftc che compila MODULI.
LIBRERIE=(-I Vendor/libwebp/include -L Vendor/libwebp/lib)

# 19/10: Rowline (le finestre in fila) dentro Complete. I suoi file si compilano a parte come libreria RowlineKit,
# così i loro nomi non si scontrano con quelli di Pulsar. Uso: kit_rowline <cartella> [flag di swiftc...],
# poi nella compilazione di Pulsar si aggiungono $(kit_flag <cartella>).
ROWLINE_KIT=(Moduli/Rowline/Kit/api.swift Moduli/Rowline/Kit/motore.swift Moduli/Rowline/Kit/tasti.swift Moduli/Rowline/Kit/pannello.swift
  Moduli/Rowline/Kit/barra.swift Moduli/Rowline/Kit/extra.swift Moduli/Rowline/Kit/reticolo.swift)
MODULI+=(Moduli/Rowline/rowline.swift)
kit_rowline() {
  local out="$1"; shift
  mkdir -p "$out"
  swiftc -parse-as-library -module-name RowlineKit -emit-module -emit-module-path "$out/RowlineKit.swiftmodule" \
    -emit-library -static -o "$out/libRowlineKit.a" "$@" $ROWLINE_KIT
}
kit_flag() { echo "-I $1 -L $1 -lRowlineKit"; }

# Fase 5, 3b: gli aggiornamenti con Sparkle (Vendor/Sparkle/LEGGIMI.md). Il file si compila in tutte e due le build,
# ma il suo codice sta dentro #if !PERSONALE: solo la vendita importa Sparkle, e solo la vendita passa questi flag.
# rpath: l'app cerca Sparkle.framework in Contents/Frameworks, dove lo copia build-vendita.sh.
MODULI+=(Moduli/Lite/aggiornamenti.swift)
SPARKLE=(-F Vendor/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
