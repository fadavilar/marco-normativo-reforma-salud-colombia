# Marco legal y normativo de la salud (contexto a la reforma)

Aplicación web estática de una sola página (HTML/CSS/JS vanilla) sobre el aseguramiento en salud en Colombia, el marco normativo del SGSSS y el estado de las EPS (activas, intervenidas para administración, intervenidas o liquidadas históricamente), en el contexto de la reforma a la salud radicada en el Congreso en julio de 2026.

## Contenido

- **Hojas 01–06**: caracterización del aseguramiento a partir de un extracto de la Base de Datos Única de Afiliados (BDUA/ADRES), 204.489 registros, 51 cortes mensuales (ene 2022 – mar 2026), por régimen, departamento, género y grupo etario.
- **Hoja 07 — Aseguradores (EPS)**: relevamiento propio e independiente del BDUA (que no trae desglose por EPS), con homologación de nombres de asegurador a su forma más simple, estado de intervención/administración/liquidación, filtros por estado y buscador, y hallazgos dinámicos y estáticos.
- **Hoja 08 — Hallazgos**: síntesis dinámica (según filtros) y estática (nacional) de la serie de afiliados.
- **Hoja 09 — Metodología y fuentes**: trazabilidad del dato, antecedentes históricos de la reforma (antes de la Ley 100, liquidaciones e intervenciones bajo tres gobiernos distintos) y bibliografía completa.

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

Ver la Hoja 09 (Metodología y fuentes) dentro de la aplicación para la bibliografía normativa y periodística completa, con enlaces.
