# PID-5 Norms Platform (formr), Version 2

A formr scoring platform for the Personality Inventory for DSM-5 and its
abbreviated versions, based on the population-representative norm tables of
Zimmermann, Kerber, Kemper, and Rek (2026). Two runs (German, English) are
generated from a common template. All scoring logic lives in a single R script
that the results pages load at runtime from a public URL.

Live versions: <https://pid5fuerendanwender.rforms.org/> (German) and
<https://pid5fortherapists.rforms.org/> (English).

## The instruments

The PID-5 (Krueger et al., 2012) measures the 25 maladaptive trait facets of
the Alternative DSM-5 Model for Personality Disorders, which are organized into
the five domains negative affectivity, detachment, antagonism, disinhibition,
and psychoticism. The platform scores four versions:

| Version | Items | Scales scored here |
|---|---|---|
| PID-5 | 220 | 25 facets, 5 domains, total score |
| PID-5-SF | 100 | 25 facets, 5 domains, total score |
| PID5BF+M | 36 | 6 domains (including anankastia), total score |
| PID-5-BF | 25 | 5 domains, total score |

Where to obtain the questionnaires. The PID-5 is distributed free of charge
for research and clinical use by the American Psychiatric Association. The
German 220-item and 25-item versions are part of the DSM-5-TR online materials
of the German publisher,
<https://www.hogrefe.com/de/downloads/dsm-5-tr-online-material>; the English
originals and the other short forms are available from the American
Psychiatric Association,
<https://www.psychiatry.org/psychiatrists/practice/dsm/educational-resources/assessment-measures>.
The German PID5BF+M is available from Freie Universität Berlin,
<https://www.ewi-psy.fu-berlin.de/psychologie/arbeitsbereiche/klinische_psychotherapie/Frageboegen/Persoenlichkeitsinventar-fuer-DSM-5-und-ICD-11_PID5BF__PID5BF_MDE/PID5BF_-M-DE-.pdf>.
This repository contains the item texts only for operating the platform; see
"License and reuse" below.

What the platform adds to the questionnaires is the normative interpretation:
percentile T scores for the German general population, conditional on age and
gender, each with a 95% interval for the person's true score.

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
ranges.

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

## Deployment (for maintainers)

This and the following section document how the runs are built, hosted, and
updated. They are internal documentation and are not needed to use the
platform.


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
   columns item, text, plus a column with the full-form item number or the
   position). The PID-5 and PID-5-SF use the item
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
   (an existing run of the same name must be renamed or deleted first),
   "Import" with `dist/pid5fuerendanwender.json`; likewise `pid5fortherapists`.
   Publish the runs, then click through all eight paths (four instruments by
   two input modes) and the reference-group variants.
7. **Norm files:** stage X1 of the norming pipeline writes the eight platform
   files (`norms_<version>.csv`, `norms_<version>_age.rds`) to
   `output/platform/`. After every production run, copy them into `assets/`
   and push; no rebuild or re-import is needed, the results pages load them at
   runtime.

## Changing texts

All texts are in `build/texts_<lang>.json`. Survey texts require a rebuild and
re-import of the run. Texts of the results page (sections `results`,
`domains`, `facets`, `instruments`, `total`) are loaded at runtime from
`<base_url>texts_<lang>.json`; updating the file in `assets/` is sufficient
(the build script copies it automatically).

## Changes relative to Version 1

Version 1 was the platform accompanying Rek, Kerber, Kemper, and Zimmermann
(2021). Version 2 replaces its norms and its implementation.

Norms:
- Population-representative norms for all four versions, conditional on age and
  gender, from a probability-based sample (GESIS Panel, N = 4,727) instead of
  the earlier quota-based basis.
- Facets and total scores in addition to the domain scales, and the PID5BF+M
  including anankastia.
- Every printed value carries its uncertainty: a credible band for the norm
  value and a 95% interval for the person's true score.
- Extrapolation flag, flag for incomplete scales.
- Three reference frames: general population, gender by age group, and gender
  by year of age (continuous-age norms).

Implementation:
- One scoring script instead of fourfold duplicated code, loaded at runtime, so
  corrections take effect without re-importing the runs.
- Two languages generated from one source of texts.
- Norm files produced directly by the norming pipeline (stage X1).
- T-based profile display with intervals for domains and facets, and
  interpretation notes following the manuscript.

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
American Psychiatric Association (see the links under "The instruments"). They are included here solely for operating
this scoring platform. Further use is governed by the terms of use of the
American Psychiatric Association; the MIT License of this repository does not
extend to them. The German translation of the PID-5 is that of Zimmermann et
al. (2014).

Anyone who wants to use the norms programmatically without running this
platform will find the complete tables in the Zenodo archive; an integration
into the R package `hitop` (Girard, 2026) is planned.

## References

Girard, J. M. (2026). *hitop: Tools for the Hierarchical Taxonomy of
Psychopathology* [R package].

Krueger, R. F., Derringer, J., Markon, K. E., Watson, D., & Skodol, A. E.
(2012). Initial construction of a maladaptive personality trait model and
inventory for DSM-5. *Psychological Medicine, 42*(9), 1879–1890.
<https://doi.org/10.1017/S0033291711002674>

Rek, K., Kerber, A., Kemper, C. J., & Zimmermann, J. (2021). *Getting the
Personality Inventory for DSM-5 ready for clinical practice: Norm values and
correlates in a representative sample from the German population* [Preprint].
PsyArXiv. <https://doi.org/10.31234/osf.io/5hm43>

Zimmermann, J., Altenstein, D., Krieger, T., Grosse Holtforth, M., Pretsch, J.,
Alexopoulos, J., Spitzer, C., Benecke, C., Krueger, R. F., Markon, K. E., &
Leising, D. (2014). The structure and correlates of self-reported DSM-5
maladaptive personality traits: Findings from two German-speaking samples.
*Journal of Personality Disorders, 28*(4), 518–540.
<https://doi.org/10.1521/pedi_2014_28_130>

Zimmermann, J., Kerber, A., Kemper, C. J., & Rek, K. (2026). *Getting the
Personality Inventory for DSM-5 ready for clinical practice:
Population-representative norms that embrace uncertainty* [Manuscript under
review]. Norm tables archived at <https://doi.org/10.5281/zenodo.22280403> and
<https://osf.io/hwxnj>.
