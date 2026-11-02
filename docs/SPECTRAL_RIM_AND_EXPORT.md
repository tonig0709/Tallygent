# Build 62 — spectral rim, focused Planner and viewable exports

Local test increment, not a public Release. Preserve build 61 material curves,
preference keys, the three panel footprints, pointer intensity, drag/close/hover,
account collection, history and Planner engine/storage.

## Spectral rim references

Primary GitHub sources inspected on 2026-11-03 (all MIT). These are algorithmic
references, not bundled dependencies or copied shader code:

- [liquid-glass-react](https://github.com/rdev/liquid-glass-react/blob/ac48eab18d1f7f444ae30002d240cae29c863a21/src/index.tsx): separate wavelength response, softened edge masking and local pointer lighting.
- [drei MeshTransmissionMaterial](https://github.com/pmndrs/drei/blob/bf6f4addf47467d3885de272d94ca5127f6ef68f/src/core/MeshTransmissionMaterial.tsx): small RGB index differences and an explicit zero-aberration path.
- [three.js transmission](https://github.com/mrdoob/three.js/blob/e02b502efd394f5e982103159b9815b2ed147aad/src/renderers/shaders/ShaderChunk/transmission_pars_fragment.glsl.js): per-wavelength refraction around the same underlying surface.
- [glass-optics](https://github.com/sohumsuthar/liquid-glass/blob/fb0e2dd45c1c76f2385dabffbb448c1099cd19cc/lib/glass-optics.mjs): bevel-localized spectral differences and grazing-angle reflection.

Tallygent replaces two translated red/cyan outlines with five muted, narrow
spectral bands on the same continuous rounded contour. A smooth directional
light mask leaves most of the perimeter quiet; pointer light only reinforces
the nearby bevel and obeys the existing global intensity and Reduce Motion.
This is a spectral *reflection approximation*, not wallpaper RGB refraction.
No screen capture permission, private API, browser engine or new package is
introduced. Zero dispersion paints no extra pixels; the center is untouched.

## Planner

Task, preference and Generate remain primary. Task category, context, profile
and reserve move into Task Options; a custom indicator exposes hidden overrides.
Recommendation details and history are expandable. Warnings, confidence
limitations, title-saving consent, errors and actions remain visible. No engine
policy or persisted task schema changes; drafts remain mounted across sections.

## Usage exports

- HTML: standalone, localized SVG report, browser-viewable and printable to PDF.
  Axes include remaining percentage and local dates/time zone. Missing reads,
  resets, quota increases and context changes do not create connecting lines.
  Charts sample within continuous segments and show at most 128 recent series,
  with an explicit notice; CSV/JSON retain all raw records.
- CSV: UTF-8 BOM, quoted cells, escaped quotes and spreadsheet formula hardening;
  original fields plus remaining percentage, explicit UTC timestamps.
- JSON: the existing raw schema and bytes remain unchanged.

All exports use the bounded 30-day history export, not the 20,000-row UI slice.
HTML escapes metadata and permits no scripts or external resources. Input and
output retain the 128 MiB budget. Account/session fingerprints remain
pseudonymous identifiers, not encryption; the report warns about sharing and
does not imply downloaded files auto-expire.

## Regression

Keep the full three-OS gate. Add spectral visibility/center confinement/zero
pointer tests, export format/escaping/scope/reset/gap tests, and existing native
Planner layout tests with options expanded. Actual desktop optics still require
the user's install acceptance; cached render tests do not prove wallpaper
sampling.
