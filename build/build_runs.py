#!/usr/bin/env python3
"""
build_runs.py

Generates the formr run definitions (importable JSON) of the PID-5 norms
platform for every language configured in config.json.

    python3 build/build_runs.py            # writes dist/<run_name>.json

Inputs
  build/config.json            hosting URL, run names, contact data
  build/texts_<lang>.json      all user-facing texts (also loaded by the R code)
  build/items/items_<version>_<lang>.tsv   item texts (item<TAB>text, header row)
  build/template_endpage.Rmd   results page template

Outputs
  dist/<run_name>.json         formr run export, import via "Import run"
  assets/texts_<lang>.json     copy of the text resources for hosting

Run structure (positions)
  10      intro survey (instrument, input mode, reference group, age, gender)
  11-18   SkipForward: route to the item survey or the sum-score survey
  20/22   full: items / sums    -> 80  results page
  30/32   sf:   items / sums    -> 82
  40/42   bfplus_m: items / sums -> 84
  50/52   bf:   items / sums    -> 86
"""

import csv
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ASSETS = os.path.join(ROOT, "assets")
DIST = os.path.join(ROOT, "dist")

VERSIONS = ["full", "sf", "bfplus_m", "bf"]
INSTRUMENT_CODE = {"full": "1", "sf": "2", "bfplus_m": "3", "bf": "4"}
FACET_FIG_HEIGHT = {"full": 13, "sf": 13, "bfplus_m": 5, "bf": 5}

# ----------------------------------------------------------------------------
# Scale definitions (mirror pid5_platform.R; used for the sum-score surveys)
# ----------------------------------------------------------------------------
FACETS_FULL = {
    "anhedonia": 8, "anxiousness": 9, "attention_seek": 8, "callousness": 14,
    "deceitfulness": 10, "depressivity": 14, "distractibility": 9, "eccentricity": 13,
    "emo_lability": 7, "grandiosity": 6, "hostility": 10, "impulsivity": 6,
    "intimacy_avoid": 6, "irresponsibility": 7, "manipulativeness": 5, "percept_dysreg": 12,
    "perseveration": 9, "restricted_aff": 7, "rigid_perfect": 10, "risk_taking": 14,
    "separation_insec": 7, "submissiveness": 4, "suspiciousness": 7, "unusual_beliefs": 8,
    "withdrawal": 10,
}
FACETS_SF = {k: 4 for k in FACETS_FULL}
DOMAINS_BF = {"negative_affectivity": 5, "detachment": 5, "antagonism": 5,
              "disinhibition": 5, "psychoticism": 5}
DOMAINS_BFM = {"negative_affectivity": 6, "detachment": 6, "antagonism": 6,
               "disinhibition": 6, "psychoticism": 6, "anankastia": 6}

# Display order of facets on the sum-score page: grouped by domain, primary first
FACET_ORDER = [
    "emo_lability", "anxiousness", "separation_insec", "hostility", "perseveration", "submissiveness",
    "withdrawal", "anhedonia", "intimacy_avoid", "restricted_aff", "depressivity", "suspiciousness",
    "manipulativeness", "deceitfulness", "grandiosity", "callousness", "attention_seek",
    "irresponsibility", "impulsivity", "distractibility", "risk_taking", "rigid_perfect",
    "unusual_beliefs", "eccentricity", "percept_dysreg",
]
DOMAIN_ORDER = ["negative_affectivity", "detachment", "antagonism", "disinhibition",
                "psychoticism", "anankastia"]

SCALE_ENTRY = {  # (level, {scale: n_items})
    "full": ("facet", FACETS_FULL),
    "sf": ("facet", FACETS_SF),
    "bfplus_m": ("domain", DOMAINS_BFM),
    "bf": ("domain", DOMAINS_BF),
}

# Item survey paging (items per page), as in the previous platform version
ITEM_PAGES = {"full": [32, 32, 31, 31, 31, 31, 32], "sf": [34, 33, 33], "bfplus_m": [36], "bf": [25]}

SURVEY_SETTINGS = {
    "maximum_number_displayed": 0, "displayed_percentage_maximum": 100,
    "add_percentage_points": 0, "enable_instant_validation": 1, "expire_after": 0,
    "google_file_id": None, "unlinked": 0, "expire_invitation_after": 0,
    "expire_invitation_grace": 0, "hide_results": 0, "use_paging": 0,
}

# ----------------------------------------------------------------------------
# Item factories
# ----------------------------------------------------------------------------

def item(itype, name, label="", **kw):
    it = {
        "type": itype, "choice_list": None, "type_options": None, "name": name,
        "label": label, "label_parsed": label, "optional": 1 if itype in ("note",) else 0,
        "class": "", "showif": "", "value": "", "block_order": None, "item_order": 0,
    }
    it.update(kw)
    return it


def note(name, label):
    return item("note", name, label)


def submit(name, label):
    return item("submit", name, label)


def mc(name, label, choices, optional=0, showif="", cls=""):
    return item("mc", name, label, choice_list=name, choices=choices, optional=optional,
                showif=showif, **{"class": cls})


def number(name, label, lo, hi, step=1, optional=0, showif=""):
    return item("number", name, label, type_options=f"{lo},{hi},{step}", optional=optional,
                showif=showif)


def block(name, label, showif):
    return item("block", name, label, showif=showif)


def finalize(items):
    for i, it in enumerate(items, start=1):
        it["item_order"] = i
    return items


# ----------------------------------------------------------------------------
# Unit factories
# ----------------------------------------------------------------------------

def survey_unit(position, name, items, use_paging=0, pct=(0, 100)):
    """pct = (add_percentage_points, displayed_percentage_maximum): the range of
    the progress bar this survey covers, so that intro and input page add up."""
    settings = dict(SURVEY_SETTINGS)
    settings["use_paging"] = use_paging
    settings["add_percentage_points"] = pct[0]
    settings["displayed_percentage_maximum"] = pct[1]
    return {
        "type": "Survey", "description": name, "position": position, "special": "",
        "survey_data": {"name": name, "items": finalize(items), "settings": settings},
    }


def skip_unit(position, condition, target):
    return {"type": "SkipForward", "description": "", "position": position, "special": "",
            "condition": condition, "if_true": target}


def endpage_unit(position, body):
    return {"type": "Endpage", "description": "", "position": position, "special": "", "body": body}


# ----------------------------------------------------------------------------
# HTML fragments
# ----------------------------------------------------------------------------

def header_html(cfg, texts, lang_cfg):
    logo = ""
    if cfg.get("logo_file"):
        logo = (f'<img src="{cfg["base_url"]}{cfg["logo_file"]}" alt="" '
                f'style="max-height:56px; margin-right:18px; vertical-align:middle;">')
    return (
        '<div style="display:flex; align-items:center; justify-content:space-between; '
        'border-bottom:1px solid #ccc; padding-bottom:8px; margin-bottom:12px;">'
        f'<div>{logo}<span style="font-size:1.5em; font-weight:bold; vertical-align:middle;">'
        f'{texts["meta"]["title"]}</span> '
        f'<span style="color:#666; vertical-align:middle;"> {texts["meta"]["subtitle"]}</span></div>'
        f'<div><a class="btn btn-default btn-sm" href="{lang_cfg["other_lang_url"]}">'
        f'{texts["meta"]["other_lang_label"]}</a></div></div>'
    )


def footer_html(cfg, texts):
    c = texts["common"]
    contact = c["footer_contact"].replace("{contact_email}", cfg["contact_email"]) \
                                 .replace("{contact_url}", cfg["contact_url"])
    copy = c["footer_copyright"].replace("{year}", cfg["year"])
    return f'<hr><p style="font-size:90%; color:#555;">{contact}<br>{copy}</p>'


# ----------------------------------------------------------------------------
# Surveys
# ----------------------------------------------------------------------------

def intro_survey(position, prefix, cfg, texts, header):
    I = texts["intro"]
    frame_choices = dict(I["frame_choices"])
    if not cfg.get("enable_continuous_age", False):
        frame_choices.pop("age", None)
    items = [
        note("header", header),
        note("intro_text", f'<h3>{I["heading"]}</h3>\n{I["text"]}'),
        note("credits", I["credits"]),
        note("settings_head", f'<h3>{I["settings_heading"]}</h3>'),
        mc("instrument", I["instrument_label"], I["instrument_choices"]),
        mc("mode", I["mode_label"], I["mode_choices"]),
        mc("frame", I["frame_label"], frame_choices),
        note("frame_help", f'<p style="font-size:90%; color:#555;">{I["frame_help"]}</p>'),
        number("age", I["age_label"], 18, 110, 1, showif='frame != "overall"'),
        mc("gender", I["gender_label"], I["gender_choices"], showif='frame != "overall"'),
        note("gender_help", f'<p style="font-size:90%; color:#555;">{I["gender_help"]}</p>',
             ),
        submit("submit_intro", texts["common"]["next"]),
    ]
    items[10]["showif"] = 'frame != "overall"'
    return survey_unit(position, f"{prefix}_intro", items, pct=(0, 15))


def scores_survey(position, prefix, version, texts, header):
    S = texts["scores"]
    level, scales = SCALE_ENTRY[version]
    order = FACET_ORDER if level == "facet" else DOMAIN_ORDER
    labels = texts["facets"] if level == "facet" else texts["domains"]
    items = [
        note("header", header),
        note("instruction", f'<h3>{S["heading"]}: {texts["instruments"][version]}</h3>\n{S["instruction"]}'),
        mc("coding", S["coding_label"], S["coding_choices"]),
        mc("complete", S["complete_label"], S["complete_choices"]),
    ]
    for sc in order:
        if sc not in scales:
            continue
        n = scales[sc]
        items.append(number(f"s_{sc}", S["sum_label"].replace("{scale}", labels[sc]).replace("{n}", str(n)),
                            0, 4 * n, 1))
        # shown only if not all items were answered; an untouched or hidden
        # field is stored as NA and treated as 0 by the scoring code
        m_item = number(f"m_{sc}", S["missing_label"].replace("{scale}", labels[sc]), 0, n, 1,
                        optional=1, showif="complete == 0")
        m_item["value"] = "0"
        items.append(m_item)
        m_safe = f"ifelse(is.na(m_{sc}), 0, m_{sc})"
        items.append(block(f"e1_{sc}", S["error_too_many_missing"].replace("{n}", str(n)),
                           f"isTRUE({m_safe} > {n})"))
        items.append(block(f"e2_{sc}", S["error_sum_too_high"],
                           f"isTRUE(s_{sc} > (3 + isTRUE(coding == 1)) * ({n} - {m_safe}))"))
    items.append(submit("submit_scores", texts["common"]["next"]))
    return survey_unit(position, f"{prefix}_scores_{version}", items, pct=(15, 100))


def load_items(version, lang):
    path = os.path.join(HERE, "items", f"items_{version}_{lang}.tsv")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as f:
        rows = list(csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE))
    rows = rows[1:] if rows and rows[0][0].lower() == "item" else rows
    return [(int(r[0]), r[1]) for r in rows if len(r) >= 2 and r[0].strip()]


def items_survey(position, prefix, version, lang, texts, header, warnings):
    IT = texts["items"]
    options = texts["common"]["response_options"]
    rows = load_items(version, lang)
    n_expected = {"full": 220, "sf": 100, "bfplus_m": 36, "bf": 25}[version]
    if rows is None or len(rows) != n_expected:
        warnings.append(f"[{lang}/{version}] item texts missing or incomplete "
                        f"(expected {n_expected}); placeholders inserted.")
        if rows is None:
            rows = [(k, f"[item {k}: text missing]") for k in range(1, n_expected + 1)]
    items = [
        note("header", header),
        note("instruction", f'<h3>{IT["heading"]}: {texts["instruments"][version]}</h3>\n<p>{IT["instruction"]}</p>'),
        note("clinician_note", IT["clinician_note"]),
    ]
    pages = ITEM_PAGES[version]
    idx = 0
    for p, n_page in enumerate(pages, start=1):
        items.append(item("mc_heading", f"head_{p}", "", choice_list=f"head_{p}", choices=options,
                          **{"class": "left400 answer_align_left mc_width80"}))
        for k, text in rows[idx: idx + n_page]:
            items.append(mc(f"pid5_{k}", text, options, optional=1,
                            cls="hide_label\nmc_width80\nlabel_align_left\nleft400"))
        idx += n_page
        items.append(submit(f"submit_{p}", texts["common"]["next"]))
    use_paging = 1 if len(pages) > 1 else 0   # paged surveys run their own 0 to 100 bar
    return survey_unit(position, f"{prefix}_items_{version}", items, use_paging=use_paging, pct=(15, 100))


def formr_vars(version):
    """Every survey column the results page needs, as a space-separated word list.
    formr includes a column only if its name (or its stem without a trailing
    _<digits>, e.g. 'pid5' for pid5_1..pid5_220) occurs as a word in the page."""
    level, scales = SCALE_ENTRY[version]
    names = ["instrument", "mode", "frame", "age", "gender", "coding", "complete", "pid5"]
    for sc in scales:
        names += [f"s_{sc}", f"m_{sc}"]
    return " ".join(names)


def endpage_body(template, cfg, texts, lang, lang_cfg, version, prefix, header):
    reset_url = lang_cfg["run_url"].rstrip("/") + "/logout"
    repl = {
        "{{FORMR_VARS}}": formr_vars(version),
        "{{HEADER_HTML}}": header,
        "{{BASE_URL}}": cfg["base_url"],
        "{{LANG}}": lang,
        "{{VERSION}}": version,
        "{{INTRO_SURVEY}}": f"{prefix}_intro",
        "{{ITEMS_SURVEY}}": f"{prefix}_items_{version}",
        "{{SCORES_SURVEY}}": f"{prefix}_scores_{version}",
        "{{FACET_FIG_HEIGHT}}": str(FACET_FIG_HEIGHT[version]),
        "{{LOAD_ERROR}}": texts["results"]["load_error"],
        "{{RESET_URL}}": reset_url,
        "{{RESET_LABEL}}": texts["common"]["reset_link"],
        "{{PRINT_LABEL}}": texts["common"]["print_link"],
    }
    body = template
    for k, v in repl.items():
        body = body.replace(k, v)
    return body


# ----------------------------------------------------------------------------
# Run assembly
# ----------------------------------------------------------------------------

def build_run(lang, cfg, warnings):
    lang_cfg = cfg["runs"][lang]
    prefix = lang_cfg["survey_prefix"]
    with open(os.path.join(HERE, f"texts_{lang}.json"), encoding="utf-8") as f:
        texts = json.load(f)
    with open(os.path.join(HERE, "template_endpage.Rmd"), encoding="utf-8") as f:
        template = f.read()
    header = header_html(cfg, texts, lang_cfg)
    intro = f"{prefix}_intro"

    units = [intro_survey(10, prefix, cfg, texts, header)]

    # routing after the intro
    pos_items = {"full": 20, "sf": 30, "bfplus_m": 40, "bf": 50}
    pos_end = {"full": 80, "sf": 82, "bfplus_m": 84, "bf": 86}
    p = 11
    for v in VERSIONS:
        code = INSTRUMENT_CODE[v]
        units.append(skip_unit(p, f"{intro}$instrument == {code} & {intro}$mode == 2", pos_items[v]))
        units.append(skip_unit(p + 1, f"{intro}$instrument == {code} & {intro}$mode == 1", pos_items[v] + 2))
        p += 2

    for v in VERSIONS:
        pi = pos_items[v]
        units.append(items_survey(pi, prefix, v, lang, texts, header, warnings))
        units.append(skip_unit(pi + 1, "TRUE", pos_end[v]))
        units.append(scores_survey(pi + 2, prefix, v, texts, header))
        units.append(skip_unit(pi + 3, "TRUE", pos_end[v]))

    for v in VERSIONS:
        units.append(endpage_unit(pos_end[v],
                                  endpage_body(template, cfg, texts, lang, lang_cfg, v, prefix, header)))

    units.sort(key=lambda u: u["position"])

    run = {
        "name": lang_cfg["run_name"],
        "units": units,
        "settings": {
            "header_image_path": None, "description": texts["meta"]["subtitle"],
            "footer_text": footer_html(cfg, texts), "public_blurb": None, "privacy": None,
            "tos": None, "cron_active": 1, "custom_js": "", "custom_css": "", "custom_r": "",
            "secrets": [], "expiresOn": "2031-12-31",
        },
        "files": [],
    }
    return run, texts


def main():
    with open(os.path.join(HERE, "config.json"), encoding="utf-8") as f:
        cfg = json.load(f)
    if not cfg["base_url"].endswith("/"):
        sys.exit("config.json: base_url must end with '/'")
    os.makedirs(DIST, exist_ok=True)
    warnings = []
    for lang in cfg["runs"]:
        run, texts = build_run(lang, cfg, warnings)
        out = os.path.join(DIST, f'{run["name"]}.json')
        with open(out, "w", encoding="utf-8") as f:
            json.dump(run, f, ensure_ascii=False, indent=2)
        # host copies of the text resource and item texts next to the norm files
        shutil.copy(os.path.join(HERE, f"texts_{lang}.json"), os.path.join(ASSETS, f"texts_{lang}.json"))
        for v in VERSIONS:
            src = os.path.join(HERE, "items", f"items_{v}_{lang}.tsv")
            if os.path.exists(src):
                shutil.copy(src, os.path.join(ASSETS, f"items_{v}_{lang}.tsv"))
        n_units = len(run["units"])
        print(f"wrote {out}  ({n_units} units, {os.path.getsize(out)/1e6:.2f} MB)")
    for w in warnings:
        print("WARNING:", w)
    if "GITHUB-USER/" in cfg["base_url"]:
        print("WARNING: base_url in config.json still contains the placeholder 'GITHUB-USER/'.")


if __name__ == "__main__":
    main()
