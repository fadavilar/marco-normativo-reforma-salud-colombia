#!/usr/bin/env bash
# Inyecta meta.json + epsdata_b64.txt (generados por build-data.ps1) en index.html,
# reemplazando las líneas `window.__DATA_META__ = ...;` y `window.__DATA_B64__ = ...;`.
#
# Uso:
#   scripts/inject-data.sh <index.html> <meta.json> <epsdata_b64.txt> [salida.html]
#
# Si no se indica archivo de salida, sobrescribe el index.html de entrada (se hace un
# respaldo .bak junto al original). Requiere bash + awk (en Windows: Git Bash).
set -euo pipefail

HTML_IN="${1:?Falta ruta a index.html}"
META_JSON="${2:?Falta ruta a meta.json}"
B64_TXT="${3:?Falta ruta a epsdata_b64.txt}"
HTML_OUT="${4:-$HTML_IN}"

# meta.json suele traer BOM UTF-8 al generarse con PowerShell; awk no lo maneja bien.
META_NOBOM="$(mktemp)"
tail -c +4 "$META_JSON" > "$META_NOBOM" 2>/dev/null || cp "$META_JSON" "$META_NOBOM"
head -c 3 "$META_JSON" | grep -q $'\xef\xbb\xbf' || cp "$META_JSON" "$META_NOBOM"

TMP_OUT="$(mktemp)"
awk -v metafile="$META_NOBOM" -v b64file="$B64_TXT" '
BEGIN{
  getline metaLine < metafile
  getline b64Line < b64file
}
/^window\.__DATA_META__ = /{ print "window.__DATA_META__ = " metaLine ";"; next }
/^window\.__DATA_B64__ = /{ print "window.__DATA_B64__ = \"" b64Line "\";"; next }
{ print }
' "$HTML_IN" > "$TMP_OUT"

rm -f "$META_NOBOM"

if [ "$HTML_OUT" = "$HTML_IN" ]; then
  cp "$HTML_IN" "$HTML_IN.bak"
fi
mv "$TMP_OUT" "$HTML_OUT"
echo "Listo: $HTML_OUT actualizado (respaldo: ${HTML_IN}.bak si se sobrescribió)."
