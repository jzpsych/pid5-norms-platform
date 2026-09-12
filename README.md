# PID-5 Norms Platform (formr), Version 3

A rebuilt formr scoring platform for the PID-5, PID-5-SF, PID5BF+M, and PID-5-BF
based on the norm tables of Zimmermann, Kerber, Kemper, and Rek (2026). Two
runs (German, English) are generated from a common template. All scoring logic
lives in a single R script that the results pages load at runtime from a public
URL.

Live versions: <https://pid5fuerendanwender.rforms.org/> (German) and
<https://pid5fortherapists.rforms.org/> (English).

## Directory structure

```
assets/                    Everything that must be hosted publicly (base_url)
  pid5_platform.R          Scoring, norm lookup, tables, figures (central logic)
  norms_<version>.csv      Reduced norm tables per instrument (stage X1 of the pipeline, output/platform/)
  norms_<version>_age.rds  Continuous-age norms (optional; see below)
  texts_de.json, texts_en.json   All texts (copied from build/, loaded by the R script)
  items_<version>_<lang>.tsv     Item texts for the list "Items with the highest endorsement"
  logo_uni_kassel.png      Logo for the page header (file name set in config.json)
build/
  config.json              base_url, run names, contact data, switch for continuous-age norms
  texts_de.json, texts_en.json   Single source of all texts (surveys and results page)
  template_endpage.Rmd     Results page template (about 50 lines, calls the pf_* functions)
  items/items_<version>_<lang>.tsv   Item texts (item<TAB>text), German and English
  build_runs.py            Generates dist/<run>.json for every language
dist/
  pid5fuerendanwender.json, pid5fortherapists.json   Importable formr runs
test/
  run_local_test.R         Knits results pages locally with mock data (without formr)
```

## Flow of a run

```
10     Intro: instrument, input mode, reference group, age, gender
11-18  SkipForward to the matching input page
20/22  PID-5:    items / sum scores  -> 80  results page
30/32  PID-5-SF: items / sum scores  -> 82
40/42  PID5BF+M: items / sum scores  -> 84   (entry at the domain level)
50/52  PID-5-BF: items / sum scores  -> 86
```

Every input page is a separate survey with exactly matching items and value
ranges. This removes the cross-version showif constructions and the hidden
field set by JavaScript in the previous version.

## What the results page reports

For every scale (domains, total score, and for the PID-5 and PID-5-SF also the
facets): items answered / items in the scale, sum, mean (the raw-score metric
of the norm tables), T score (percentile of the observed raw score, column
`T`), 95% credible interval (fully integrated interval, columns `T_int_lo`,
`T_int_hi`), and percentile (`pctl_med`). Flags: fewer than 80% of items
answered (a), extrapolated norm value (b). Figures: profile of the domains and
(PID-5, PID-5-SF) of the facets with intervals and reference lines at T = 50,
60, 65, 70. With item input additionally: the list of items with the highest
endorsement.

Total score: mean of all items of the five DSM-5 domains (220 / 100 / 25 / 30
items, Anankastia not included), table level `total`. With sum-score input it
is computed from the entered facet or domain sums and the counts of missing
items. It appears as the last row of the domain table and as a separated
diamond in the domain profile.

Reference group: general population, gender by age group, or gender by year
of age (continuous-age norms). Because the tables contain no pure age or
gender norms, both entries are required for the two specific frames. Gender
"diverse/not specified" or a missing age fall back to the general population
norms, with a note.

Continuous-age norms: the T score and percentile come from the kernel-weighted
tables of pipeline stage M3b (per year of age, 18 to 85; ages above 85 use the
row for 85). These tables carry no integrated individual interval unless the
pipeline is extended to compute one per year of age. If the columns
`T_int_lo`/`T_int_hi` are present in `norms_<version>_age.rds`, the platform
uses them directly; otherwise it transfers the integrated interval of the
gender by age-band cell and centres it on the age-specific T score (same width
and asymmetry; marked as an approximation in a footnote). If the file for an
instrument is missing, the platform falls back to the age-band norms and says
so. The option is shown in the intro when `enable_continuous_age` is true in
config.json.

## Deployment

1. **Hosting the assets.** Recommended: a public GitHub repository holding this
   project. Then `base_url` is the raw URL of the `assets/` folder, for example
   `https://raw.githubusercontent.com/<user>/pid5-norms-platform/main/assets/`.
   Advantages: versioned, updatable without re-import (text corrections, bug
   fixes), independent of the formr host. Releases can be archived
   automatically through the GitHub-Zenodo integration. Alternatives: OSF
   (upload files individually and enter the download URLs; then
   `pf_read_url()` needs an explicit URL per file) or the file upload of the
   target formr instance (then the run is tied to that instance).
2. **Adjust config.json:** replace the placeholder `GITHUB-USER` in `base_url`
   with the GitHub account (and the repository name if it differs). Run names
   and URLs are already set to `pid5fuerendanwender.rforms.org` and
   `pid5fortherapists.rforms.org`.
3. **Item texts** are in `build/items/items_<version>_<lang>.tsv` (generated
   from `pid-5_dt_englisch.xlsx`; columns item, text, plus a column with the
   full-form item number or the position). The PID-5 and PID-5-SF use the item
   numbers of the 220-item form as item names (`pid5_<k>`); SF items are
   presented in the official SF order. BF and BF+M use positions 1 to 25 and
   1 to 36. The assignments were checked against the scale keys of the norming
   pipeline.
4. **Build:** `python3 build/build_runs.py` writes `dist/*.json` and copies
   texts and item texts to `assets/`. Take warnings about missing item texts
   seriously: placeholder texts would otherwise be imported.
5. **Publish the assets** (git push), then check that
   `<base_url>pid5_platform.R` and `<base_url>norms_full.csv` load in a browser.
6. **Import into formr (rforms.org):** create a new run `pid5fuerendanwender`
   (the existing run of the same name must be renamed or deleted first),
   "Import" with `dist/pid5fuerendanwender.json`; likewise `pid5fortherapists`.
   Publish the runs, then click through all eight paths (four instruments by
   two input modes) and the reference-group variants.
7. **Norm files:** stage X1 of the norming pipeline writes the eight platform
   files (`norms_<version>.csv`, `norms_<version>_age.rds`) to
   `output/platform/`. After every production run, copy them into `assets/`
   and push; no rebuild or re-import is needed, the results pages load them at
   runtime.

## Local testing without formr

Requirements: R with ggplot2, jsonlite, knitr, rmarkdown, and pandoc.

```
Rscript test/run_local_test.R de full items cell f 29
Rscript test/run_local_test.R en bf scores overall f 50
Rscript test/run_local_test.R de bfplus_m scores cell m 71
```

Arguments: language, version (full, sf, bfplus_m, bf), mode (items, scores),
reference group (overall, cell, age), gender (m, f, d), age. Output in
`test/out/*.html`. The script replaces `base_url` with the local `assets/`
folder; everything else is identical to live operation. The T scores and
intervals of the test cases were spot-checked against `norm_tables_long.csv`.

## Changing texts

All texts are in `build/texts_<lang>.json`. Survey texts require a rebuild and
re-import of the run. Texts of the results page (sections `results`,
`domains`, `facets`, `instruments`, `total`) are loaded at runtime from
`<base_url>texts_<lang>.json`; updating the file in `assets/` is sufficient
(the build script copies it automatically).

## Changes relative to Version 2

Fixed:
- Intervals: `T_int_lo`/`T_int_hi` instead of `T_lo`/`T_hi` (the old ones were about four times too narrow in the median).
- Reference group: age without gender returned NA; gender without age silently used the norms of the 18 to 34 age group. Now an explicit choice with a defined fallback to the general population norms.
- Coding 1 to 4: one point was subtracted instead of the number of answered items.
- Range checks of the sum scores are now correct per instrument.

Removed:
- Toggles "model-implied values" and "percentiles" (the percentile is now a table column; intervals are always shown).
- Old norms (N = 1288, Tiefenbrunn comparison, common-metric text).
- Hard-coded URLs on formr.org/rforms.org.
- Fourfold duplicated code (about 6000 lines) in favor of one script.

New:
- PID5BF+M: entry and scoring at the domain level including Anankastia.
- Extrapolation flag, flag for incomplete scales.
- T-based profile display with intervals for domains and facets.
- Interpretation notes following the manuscript (judge the interval; regression effect at extreme scores).
- Two languages from one source; texts as a resource.
- Norm files produced directly by the pipeline (stage X1, folder platform/).
- Continuous-age norms as a third reference frame (T from the kernel tables, interval transferred from the age-band cell unless the pipeline supplies integrated intervals per year of age).
- Total score (norm tables of 2026-09-05, 32,967 rows, including the tick fix of the directly observed PID5BF+M norms).

## License and reuse

This repository contains three kinds of content with different terms.

**Code** (`assets/pid5_platform.R`,
`build/build_runs.py`, `build/template_endpage.Rmd`, `test/run_local_test.R`):
MIT License, see `LICENSE`. Reuse, modification, and integration into other
applications are welcome.

**Norm tables** (`assets/norms_*.csv`): CC BY 4.0. They are an excerpt of the
tables from Zimmermann, J., Kerber, A., Kemper, C. J., & Rek, K. (2026),
*Getting the Personality Inventory for DSM-5 ready for clinical practice:
Population-representative norms that embrace uncertainty*, archived at
<https://doi.org/10.5281/zenodo.22280403> and <https://osf.io/hwxnj>. Please
cite this source when reusing them. The files stored here are reduced to the
columns needed by the platform and rounded; for analytic purposes, use the
complete tables from the archive.

**Item texts** (`assets/items_*.tsv`, and the questionnaire pages generated
from them in `dist/*.json`): The items of the PID-5 are copyrighted by the
American Psychiatric Association. They are included here solely for operating
this scoring platform. Further use is governed by the terms of use of the
American Psychiatric Association; the MIT License of this repository does not
extend to them. The German translation is from Zimmermann, J., Altenstein, D.,
Krieger, T., Grosse Holtforth, M., Pretsch, J., Alexopoulos, J., Spitzer, C.,
Benecke, C., Krueger, R. F., Markon, K. E., & Leising, D. (2014). The structure
and correlates of self-reported DSM-5 maladaptive personality traits: Findings
from two German-speaking samples. *Journal of Personality Disorders, 28*(4),
518–540. <https://doi.org/10.1521/pedi_2014_28_130>

Anyone who wants to use the norms programmatically without running this
platform will find the complete tables in the Zenodo archive; an integration
into the R package `hitop` (Girard, 2026) is planned.
