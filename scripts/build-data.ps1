<#
.SYNOPSIS
  Convierte un extracto BDUA (.xlsx) en los tres artefactos que consume index.html:
  epsdata.bin (binario empaquetado), epsdata_b64.txt (ese binario en base64) y meta.json
  (catálogos: periodos, regímenes, departamentos, géneros, grupos etarios y aseguradoras).

.DESCRIPTION
  Este script fue el usado para generar la serie de datos embebida en index.html
  (window.__DATA_META__ / window.__DATA_B64__). Se documenta aquí para que el análisis
  sea reproducible con una fuente BDUA propia, sin depender del archivo original.

  Formato de entrada esperado (hoja única, fila 1 = encabezados):
    A Departamento | B Estado Afiliación BDUA (se ignora) | C Género BDUA | D EPS
    E Grupo Etario | F Periodo (p.ej. "Ene 2022")          | G Régimen Administradora BDUA
    H #Tendencia Afiliados (conteo numérico)

  Estrategia: en vez de cargar el .xlsx con una librería de Excel, se lee directamente
  xl/sharedStrings.xml y xl/worksheets/sheet1.xml del .zip (formato OOXML) y se extraen
  las celdas con una expresión regular — mucho más rápido que un parser XML por DOM para
  archivos de cientos de miles de filas.

  Codificación del binario (6 arreglos de 1 byte por fila + 1 arreglo de 4 bytes por fila,
  todos de longitud n, concatenados en este orden): departamento, régimen, género,
  grupo etario, periodo, asegurador, conteo (UInt32 little-endian). index.html decodifica
  este layout en buildDB().

.PARAMETER XlsxPath
  Ruta al extracto BDUA (.xlsx) de origen.

.PARAMETER OutDir
  Carpeta donde se escriben epsdata.bin, epsdata_b64.txt y meta.json. Por defecto, la
  carpeta "data" junto a este script.

.EXAMPLE
  powershell -File scripts/build-data.ps1 -XlsxPath "C:\ruta\extracto_bdua.xlsx"

.EXAMPLE
  # Inyectar el resultado en index.html (requiere bash/awk, p.ej. Git Bash en Windows):
  #   ver scripts/inject-data.sh
#>
param(
  [Parameter(Mandatory=$true)]
  [string]$XlsxPath,

  [string]$OutDir
)

$ErrorActionPreference = "Stop"

# $PSScriptRoot no siempre está disponible como default de parámetro según el host que
# invoque el script; se resuelve aquí en el cuerpo, con un fallback al directorio actual.
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath } else { (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path $scriptDir "data" }

if (-not (Test-Path $XlsxPath)) { throw "No existe el archivo de entrada: $XlsxPath" }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($XlsxPath)

Write-Host "Leyendo sharedStrings.xml..."
$ssEntry = $zip.GetEntry("xl/sharedStrings.xml")
$ssReader = New-Object System.IO.StreamReader($ssEntry.Open(), [System.Text.Encoding]::UTF8)
[xml]$ssXml = $ssReader.ReadToEnd()
$ssReader.Close()
$ns = New-Object System.Xml.XmlNamespaceManager($ssXml.NameTable)
$ns.AddNamespace("a","http://schemas.openxmlformats.org/spreadsheetml/2006/main")
$siNodes = $ssXml.SelectNodes("//a:si", $ns)
$sharedStrings = New-Object string[] $siNodes.Count
for ($i=0; $i -lt $siNodes.Count; $i++) {
  $tNodes = $siNodes[$i].SelectNodes(".//a:t", $ns)
  $sb = New-Object System.Text.StringBuilder
  foreach ($t in $tNodes) { [void]$sb.Append($t.InnerText) }
  $sharedStrings[$i] = $sb.ToString()
}
Write-Host ("sharedStrings: {0} entradas" -f $sharedStrings.Count)

Write-Host "Leyendo sheet1.xml completo (puede tardar varios minutos en archivos grandes)..."
$sheetEntry = $zip.GetEntry("xl/worksheets/sheet1.xml")
$sheetReader = New-Object System.IO.StreamReader($sheetEntry.Open(), [System.Text.Encoding]::UTF8)
$xmlContent = $sheetReader.ReadToEnd()
$sheetReader.Close()
$zip.Dispose()
Write-Host ("sheet1.xml: {0} caracteres" -f $xmlContent.Length)

if ($xmlContent -match 'ref="A1:H(\d+)"') {
  $n = [int]$matches[1] - 1
} else {
  throw "No se pudo determinar el numero de filas (dimension ref). Verifica que la hoja tenga columnas A:H con fila 1 de encabezados."
}
Write-Host ("Filas de datos esperadas (n): {0}" -f $n)

Write-Host "Extrayendo celdas con regex..."
$re = [System.Text.RegularExpressions.Regex]::new('<c r="([A-H])\d+"[^>]*><v>(-?\d+)</v></c>', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$matchesAll = $re.Matches($xmlContent)
Write-Host ("Celdas encontradas: {0} (esperado: {1})" -f $matchesAll.Count, ($n*8 + 8))
if ($matchesAll.Count -ne ($n*8 + 8)) {
  Write-Warning "El numero de celdas no coincide con el esperado. Revisa que todas las filas tengan las 8 columnas A:H sin celdas vacias/omitidas."
}

# Arreglos de codigo "en bruto" (orden de primera aparicion) por fila
$dRaw = New-Object int[] $n
$rRaw = New-Object int[] $n
$gRaw = New-Object int[] $n
$eRaw = New-Object int[] $n
$pRaw = New-Object int[] $n
$aRaw = New-Object int[] $n
$cArr = New-Object uint32[] $n

# Mapas dinamicos (string -> codigo) en orden de primera aparicion
$depMap = @{}; $depList = New-Object System.Collections.Generic.List[string]
$regMap = @{}; $regList = New-Object System.Collections.Generic.List[string]
$genMap = @{}; $genList = New-Object System.Collections.Generic.List[string]
$grpMap = @{}; $grpList = New-Object System.Collections.Generic.List[string]
$perMap = @{}; $perList = New-Object System.Collections.Generic.List[string]
$epsMap = @{}; $epsList = New-Object System.Collections.Generic.List[string]

function Get-Code($map, $list, $key) {
  if ($map.ContainsKey($key)) { return $map[$key] }
  $code = $list.Count
  $map[$key] = $code
  [void]$list.Add($key)
  return $code
}

$totalCells = $matchesAll.Count
$rowIdx = -1
# saltar las primeras 8 celdas (fila de encabezado)
for ($i = 8; $i -lt $totalCells; $i += 8) {
  $rowIdx++
  # A=depto, B=estado(ignorar), C=genero, D=eps, E=grupo, F=periodo, G=regimen, H=count
  $depStr = $sharedStrings[[int]$matchesAll[$i+0].Groups[2].Value]
  $genStr = $sharedStrings[[int]$matchesAll[$i+2].Groups[2].Value]
  $epsStr = $sharedStrings[[int]$matchesAll[$i+3].Groups[2].Value]
  $grpStr = $sharedStrings[[int]$matchesAll[$i+4].Groups[2].Value]
  $perStr = $sharedStrings[[int]$matchesAll[$i+5].Groups[2].Value]
  $regStr = $sharedStrings[[int]$matchesAll[$i+6].Groups[2].Value]
  $cntVal = [uint32]$matchesAll[$i+7].Groups[2].Value

  $dRaw[$rowIdx] = Get-Code $depMap $depList $depStr
  $gRaw[$rowIdx] = Get-Code $genMap $genList $genStr
  $aRaw[$rowIdx] = Get-Code $epsMap $epsList $epsStr
  $eRaw[$rowIdx] = Get-Code $grpMap $grpList $grpStr
  $pRaw[$rowIdx] = Get-Code $perMap $perList $perStr
  $rRaw[$rowIdx] = Get-Code $regMap $regList $regStr
  $cArr[$rowIdx] = $cntVal

  if (($rowIdx % 200000) -eq 0) { Write-Host ("  fila {0} / {1}" -f $rowIdx, $n) }
}
Write-Host ("Filas procesadas: {0}" -f ($rowIdx+1))
Write-Host ("Departamentos distintos: {0}" -f $depList.Count)
Write-Host ("EPS distintas: {0}" -f $epsList.Count)
Write-Host ("Periodos distintos: {0}" -f $perList.Count)
Write-Host ("Generos distintos: {0}" -f $genList.Count)
Write-Host ("Grupos etarios distintos: {0}" -f $grpList.Count)
Write-Host ("Regimenes distintos: {0}" -f $regList.Count)

# --- Reordenar departamentos: alfabetico, con "-","INPEC","NO APLICA" al final ---
$depSpecial = @('-','INPEC','NO APLICA')
$depNamed = $depList | Where-Object { $depSpecial -notcontains $_ } | Sort-Object
$depFinal = @()
$depFinal += $depNamed
foreach ($s in $depSpecial) { if ($depList -contains $s) { $depFinal += $s } }
$depRemap = @{}
for ($i=0; $i -lt $depFinal.Count; $i++) { $depRemap[$depList.IndexOf($depFinal[$i])] = $i }

# --- Reordenar EPS: alfabetico ---
$epsFinal = $epsList | Sort-Object
$epsRemap = @{}
for ($i=0; $i -lt $epsFinal.Count; $i++) { $epsRemap[$epsList.IndexOf($epsFinal[$i])] = $i }

# --- Reordenar periodos: cronologico ---
$monthMap = @{ 'Ene'=1;'Feb'=2;'Mar'=3;'Abr'=4;'May'=5;'Jun'=6;'Jul'=7;'Ago'=8;'Sep'=9;'Oct'=10;'Nov'=11;'Dic'=12 }
$perInfo = @()
foreach ($lbl in $perList) {
  $parts = $lbl -split ' '
  $mon = $monthMap[$parts[0]]
  $yr = [int]$parts[1]
  $perInfo += [PSCustomObject]@{ label=$lbl; y=$yr; m=$mon }
}
$perFinalObjs = $perInfo | Sort-Object y, m
$perFinal = $perFinalObjs.label
$perRemap = @{}
for ($i=0; $i -lt $perFinal.Count; $i++) { $perRemap[$perList.IndexOf($perFinal[$i])] = $i }

# --- Regimen: orden fijo conocido, con fallback para valores nuevos al final ---
$regOrderPref = @('CONTRIBUTIVO','SUBSIDIADO','EXCEPCION','INPEC INTRAMURAL')
$regFinal = @()
foreach ($rr in $regOrderPref) { if ($regList -contains $rr) { $regFinal += $rr } }
foreach ($rr in $regList) { if ($regFinal -notcontains $rr) { $regFinal += $rr } }
$regRemap = @{}
for ($i=0; $i -lt $regFinal.Count; $i++) { $regRemap[$regList.IndexOf($regFinal[$i])] = $i }

# --- Genero: orden fijo conocido ---
$genOrderPref = @('FEMENINO','MASCULINO','NO REPORTA')
$genFinal = @()
foreach ($gg in $genOrderPref) { if ($genList -contains $gg) { $genFinal += $gg } }
foreach ($gg in $genList) { if ($genFinal -notcontains $gg) { $genFinal += $gg } }
$genRemap = @{}
for ($i=0; $i -lt $genFinal.Count; $i++) { $genRemap[$genList.IndexOf($genFinal[$i])] = $i }

# --- Grupo etario: orden fijo conocido ---
$grpOrderPref = @('DE 0 A 4 AÑOS','DE 05 A 09 AÑOS','DE 10 A 14 AÑOS','DE 15 A 19 AÑOS','DE 20 A 24 AÑOS','DE 25 A 29 AÑOS','DE 30 A 34 AÑOS','DE 35 A 39 AÑOS','DE 40 A 44 AÑOS','DE 45 A 49 AÑOS','DE 50 A 54 AÑOS','DE 55 A 59 AÑOS','DE 60 A 64 AÑOS','DE 65 A 69 AÑOS','DE 70 A 74 AÑOS','DE 75 A 79 AÑOS','DE 80 AÑOS O MÁS','NO REPORTADO','SIN GRUPO')
$grpFinal = @()
foreach ($e in $grpOrderPref) { if ($grpList -contains $e) { $grpFinal += $e } }
foreach ($e in $grpList) { if ($grpFinal -notcontains $e) { $grpFinal += $e } }
$grpRemap = @{}
for ($i=0; $i -lt $grpFinal.Count; $i++) { $grpRemap[$grpList.IndexOf($grpFinal[$i])] = $i }

Write-Host "Remapeando codigos..."
$dOut = New-Object byte[] $n
$rOut = New-Object byte[] $n
$gOut = New-Object byte[] $n
$eOut = New-Object byte[] $n
$pOut = New-Object byte[] $n
$aOut = New-Object byte[] $n
for ($i=0; $i -lt $n; $i++) {
  $dOut[$i] = [byte]$depRemap[$dRaw[$i]]
  $rOut[$i] = [byte]$regRemap[$rRaw[$i]]
  $gOut[$i] = [byte]$genRemap[$gRaw[$i]]
  $eOut[$i] = [byte]$grpRemap[$eRaw[$i]]
  $pOut[$i] = [byte]$perRemap[$pRaw[$i]]
  $aOut[$i] = [byte]$epsRemap[$aRaw[$i]]
}

Write-Host "Empaquetando binario..."
$totalBytes = ($n * 6) + ($n * 4)
$bin = New-Object byte[] $totalBytes
[Array]::Copy($dOut, 0, $bin, 0*$n, $n)
[Array]::Copy($rOut, 0, $bin, 1*$n, $n)
[Array]::Copy($gOut, 0, $bin, 2*$n, $n)
[Array]::Copy($eOut, 0, $bin, 3*$n, $n)
[Array]::Copy($pOut, 0, $bin, 4*$n, $n)
[Array]::Copy($aOut, 0, $bin, 5*$n, $n)
$cBytes = New-Object byte[] ($n*4)
[System.Buffer]::BlockCopy($cArr, 0, $cBytes, 0, $n*4)
[Array]::Copy($cBytes, 0, $bin, 6*$n, $n*4)

$binPath = Join-Path $OutDir "epsdata.bin"
[System.IO.File]::WriteAllBytes($binPath, $bin)
Write-Host ("Binario escrito: {0} bytes -> {1}" -f $bin.Length, $binPath)

$totalAfiliados = ($cArr | Measure-Object -Sum).Sum
Write-Host ("Suma total de afiliados (todas las filas/periodos): {0}" -f $totalAfiliados)

Write-Host "Generando base64..."
$b64 = [System.Convert]::ToBase64String($bin)
$b64Path = Join-Path $OutDir "epsdata_b64.txt"
[System.IO.File]::WriteAllText($b64Path, $b64)
Write-Host ("Base64 escrito: {0} caracteres -> {1}" -f $b64.Length, $b64Path)

# --- Generar META JSON ---
$periodosObj = $perFinalObjs | ForEach-Object {
  $isoMon = "{0:D2}" -f $_.m
  [PSCustomObject]@{ label=$_.label; iso="$($_.y)-$isoMon"; y=$_.y; m=$_.m }
}
$meta = [PSCustomObject]@{
  n = $n
  periodos = $periodosObj
  regimenes = $regFinal
  departamentos = $depFinal
  generos = $genFinal
  grupos = $grpFinal
  aseguradores = $epsFinal
}
$metaPath = Join-Path $OutDir "meta.json"
$meta | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $metaPath -Encoding utf8
Write-Host ("Meta escrito -> {0}" -f $metaPath)
Write-Host "LISTO. Siguiente paso: scripts/inject-data.sh para insertar estos artefactos en index.html."
