# Marco legal y normativo de la salud (contexto a la reforma)

Aplicación web estática de una sola página (HTML/CSS/JS vanilla) sobre el aseguramiento en salud en Colombia, el marco normativo del SGSSS y el estado de las EPS (activas, intervenidas para administración, intervenidas o liquidadas históricamente), en el contexto de la reforma a la salud radicada en el Congreso en julio de 2026.

## Contenido

- **Hoja 01 — Resumen general**: KPIs y gráficos nacionales, con panel plegable de metodología, definiciones, antecedentes de la reforma y bibliografía completa.
- **Hoja 02 — Marco normativo · Eje 1**: línea de tiempo normativa del SGSSS.
- **Hojas 03–06**: evolución, crecimiento por régimen, pirámide poblacional y distribución geográfica del aseguramiento, a partir de un extracto de la Base de Datos Única de Afiliados (BDUA/ADRES) — 995.485 registros, 51 cortes mensuales (ene 2022 – mar 2026), por régimen, departamento, género, grupo etario y EPS/administradora.
- **Filtros globales** (régimen, departamento y asegurador/EPS) aplican a las hojas 01 y 03–06, con nombres de EPS homologados a su forma más simple y en mayúsculas. Las EPS sin afiliados vigentes en el corte más reciente (liquidadas/absorbidas) no aparecen en el filtro. Los chips de régimen se adaptan a la EPS seleccionada.
- **Hoja 07 — Aseguradores (EPS)**: relevamiento cualitativo propio e independiente del BDUA, con homologación de nombres de asegurador, estado de intervención/administración/liquidación, filtros propios de estado y régimen, enlazado con el filtro global de EPS del encabezado, y hallazgos dinámicos y estáticos.
- **Hoja 08 — Hallazgos**: síntesis dinámica (según filtros) y estática (nacional) de la serie de afiliados.

## Cómo se generan los datos (hojas 01, 03–06)

La serie de afiliados que consumen esas hojas está embebida en `index.html` como
`window.__DATA_META__` (catálogos) y `window.__DATA_B64__` (datos empaquetados en
binario, codificados en base64). Se genera a partir de un extracto BDUA (.xlsx) con este
pipeline, documentado en `scripts/`:

```bash
# 1) Extrae el .xlsx y produce data/epsdata.bin, data/epsdata_b64.txt y data/meta.json
powershell -File scripts/build-data.ps1 -XlsxPath "C:\ruta\extracto_bdua.xlsx"

# 2) Inyecta esos artefactos en index.html (requiere bash/awk — Git Bash en Windows)
scripts/inject-data.sh index.html scripts/data/meta.json scripts/data/epsdata_b64.txt
```

`build-data.ps1` lee directamente `xl/sharedStrings.xml` y `xl/worksheets/sheet1.xml`
dentro del `.xlsx` (formato OOXML/zip) con expresiones regulares, sin depender de una
librería de Excel — necesario para procesar archivos de cientos de miles de filas en
tiempos razonables. El formato de entrada esperado (columnas A:H) está documentado en la
cabecera del script.

## Ejecutar localmente

No requiere build ni dependencias de servidor. Sirve la carpeta con cualquier servidor estático, por ejemplo:

```bash
npx serve .
```

o el script incluido `serve.ps1` (PowerShell, puerto 8845):

```powershell
powershell -File serve.ps1
```

Luego abre `http://localhost:8845/`.

## Fuentes principales

Ver el panel de Metodología (desplegable en la Hoja 01) para la bibliografía normativa y periodística completa, con enlaces.
