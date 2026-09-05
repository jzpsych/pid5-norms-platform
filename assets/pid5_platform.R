# =============================================================================
# pid5_platform.R
# Scoring and rendering logic of the PID-5 norms platform (formr results pages).
#
# This file is source()d by every results page of the German and the English
# run. All instrument-specific knowledge (item keys, scoring rules, norm
# lookup, tables, figures) lives here; the results pages only pass in the
# survey data frames and call the pf_* functions in order.
#
# Requires: ggplot2 (>= 3.4), jsonlite. Base R otherwise (no native pipe, no
# lambdas, to stay compatible with older R installations on formr hosts).
#
# Entry points (called from the results page in this order):
#   pf <- pf_run(version, lang, base_url, intro, items = NULL, scores = NULL)
#   pf_render_summary(pf)      header line: instrument, input mode, reference group
#   pf_render_tables(pf)       domain table, facet table (full and SF only)
#   pf_plot_domains(pf)        ggplot, print inside a figure chunk
#   pf_plot_facets(pf)         ggplot (full and SF only), taller figure chunk
#   pf_render_notes(pf)        interpretation notes
#   pf_render_high_items(pf)   items answered with the highest category
#
# Norm files (created by prepare_norm_assets.R):
#   <base_url>/norms_<version>.csv       cells m/f x four age groups + overall
#   <base_url>/norms_<version>_age.csv   continuous-age norms (optional)
# Text files:
#   <base_url>/texts_<lang>.json
#   <base_url>/items_<version>_<lang>.tsv  (item texts; optional)
#
# Reported quantities per scale (Zimmermann, Kerber, Kemper, & Rek, 2026):
#   T          observed-score percentile T score (column "T")
#   T_lo/T_hi  fully integrated 95% credible interval (columns T_int_lo/hi)
#   pctl       median percentile estimate (column pctl_med)
#   extrap     raw score outside the range observed in the reference sample
# =============================================================================

pf_version_tag <- "2026-09-05"

# UTF-8 output (umlauts in cat()) also on hosts with a non-UTF-8 default locale
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  for (loc in c("C.UTF-8", "en_US.UTF-8", "de_DE.UTF-8"))
    if (!is.na(suppressWarnings(Sys.setlocale("LC_CTYPE", loc))) &&
        isTRUE(l10n_info()[["UTF-8"]])) break
}

# -----------------------------------------------------------------------------
# 1. Instrument definitions
# -----------------------------------------------------------------------------
# Full PID-5 and PID-5-SF: item numbers of the 220-item form. The SF survey
# names its items with the full-form numbers as well (pid5_<k>).
# PID-5-BF and PID5BF+M: item positions of the respective form (1..25, 1..36).

pf_reverse_full <- c(7, 30, 35, 58, 87, 90, 96, 97, 98, 131, 142, 155, 164,
                     177, 210, 215)

pf_facet_key_full <- list(
  anhedonia        = c(1, 23, 26, 30, 124, 155, 157, 189),
  anxiousness      = c(79, 93, 95, 96, 109, 110, 130, 141, 174),
  attention_seek   = c(14, 43, 74, 111, 113, 173, 191, 211),
  callousness      = c(11, 13, 19, 54, 72, 73, 90, 153, 166, 183, 198, 200, 207, 208),
  deceitfulness    = c(41, 53, 56, 76, 126, 134, 142, 206, 214, 218),
  depressivity     = c(27, 61, 66, 81, 86, 104, 119, 148, 151, 163, 168, 169, 178, 212),
  distractibility  = c(6, 29, 47, 68, 88, 118, 132, 144, 199),
  eccentricity     = c(5, 21, 24, 25, 33, 52, 55, 70, 71, 152, 172, 185, 205),
  emo_lability     = c(18, 62, 102, 122, 138, 165, 181),
  grandiosity      = c(40, 65, 114, 179, 187, 197),
  hostility        = c(28, 32, 38, 85, 92, 116, 158, 170, 188, 216),
  impulsivity      = c(4, 16, 17, 22, 58, 204),
  intimacy_avoid   = c(89, 97, 108, 120, 145, 203),
  irresponsibility = c(31, 129, 156, 160, 171, 201, 210),
  manipulativeness = c(107, 125, 162, 180, 219),
  percept_dysreg   = c(36, 37, 42, 44, 59, 77, 83, 154, 192, 193, 213, 217),
  perseveration    = c(46, 51, 60, 78, 80, 100, 121, 128, 137),
  restricted_aff   = c(8, 45, 84, 91, 101, 167, 184),
  rigid_perfect    = c(34, 49, 105, 115, 123, 135, 140, 176, 196, 220),
  risk_taking      = c(3, 7, 35, 39, 48, 67, 69, 87, 98, 112, 159, 164, 195, 215),
  separation_insec = c(12, 50, 57, 64, 127, 149, 175),
  submissiveness   = c(9, 15, 63, 202),
  suspiciousness   = c(2, 103, 117, 131, 133, 177, 190),
  unusual_beliefs  = c(94, 99, 106, 139, 143, 150, 194, 209),
  withdrawal       = c(10, 20, 75, 82, 136, 146, 147, 161, 182, 186)
)

pf_facet_key_sf <- list(
  anhedonia        = c(23, 26, 124, 157),
  anxiousness      = c(79, 109, 130, 174),
  attention_seek   = c(74, 173, 191, 211),
  callousness      = c(19, 153, 166, 183),
  deceitfulness    = c(53, 134, 206, 218),
  depressivity     = c(81, 151, 163, 169),
  distractibility  = c(118, 132, 144, 199),
  eccentricity     = c(25, 70, 152, 205),
  emo_lability     = c(122, 138, 165, 181),
  grandiosity      = c(40, 114, 187, 197),
  hostility        = c(38, 92, 158, 170),
  impulsivity      = c(4, 16, 17, 22),
  intimacy_avoid   = c(89, 120, 145, 203),
  irresponsibility = c(129, 156, 160, 171),
  manipulativeness = c(107, 125, 162, 219),
  percept_dysreg   = c(44, 154, 192, 217),
  perseveration    = c(60, 80, 100, 128),
  restricted_aff   = c(84, 91, 167, 184),
  rigid_perfect    = c(105, 123, 176, 196),
  risk_taking      = c(39, 48, 67, 159),
  separation_insec = c(50, 127, 149, 175),
  submissiveness   = c(9, 15, 63, 202),
  suspiciousness   = c(2, 117, 133, 190),
  unusual_beliefs  = c(106, 139, 150, 209),
  withdrawal       = c(82, 136, 146, 186)
)

# Domain composition (primary facets, official scoring): domain score is the
# mean of the three facet means.
pf_domain_key <- list(
  negative_affectivity = c("emo_lability", "anxiousness", "separation_insec"),
  detachment           = c("withdrawal", "anhedonia", "intimacy_avoid"),
  antagonism           = c("manipulativeness", "deceitfulness", "grandiosity"),
  disinhibition        = c("irresponsibility", "impulsivity", "distractibility"),
  psychoticism         = c("unusual_beliefs", "eccentricity", "percept_dysreg")
)

# Display grouping of all 25 facets (DSM-5 Section III, Table 3): the three
# primary facets first, then the remaining facets assigned to the domain.
pf_facet_display <- list(
  negative_affectivity = c("emo_lability", "anxiousness", "separation_insec",
                           "hostility", "perseveration", "submissiveness"),
  detachment           = c("withdrawal", "anhedonia", "intimacy_avoid",
                           "restricted_aff", "depressivity", "suspiciousness"),
  antagonism           = c("manipulativeness", "deceitfulness", "grandiosity",
                           "callousness", "attention_seek"),
  disinhibition        = c("irresponsibility", "impulsivity", "distractibility",
                           "risk_taking", "rigid_perfect"),
  psychoticism         = c("unusual_beliefs", "eccentricity", "percept_dysreg")
)

# PID-5-BF (25 items, form positions): domain = mean of five items.
pf_domain_key_bf <- list(
  negative_affectivity = c(8, 9, 10, 11, 15),
  detachment           = c(4, 13, 14, 16, 18),
  antagonism           = c(17, 19, 20, 22, 25),
  disinhibition        = c(1, 2, 3, 5, 6),
  psychoticism         = c(7, 12, 21, 23, 24)
)

# PID5BF+M (36 items, form positions): 18 facet doublets, six domains.
# DSM domains = mean of the three doublet means (as in the PID5BF+);
# Anankastia = mean of its six items (Bach et al., 2020; pipeline convention).
pf_facet_key_bfm <- list(
  emo_lability = c(1, 19),  anxiousness = c(7, 25),   separation_insec = c(13, 31),
  withdrawal = c(4, 22),    anhedonia = c(10, 28),    intimacy_avoid = c(16, 34),
  manipulativeness = c(2, 20), deceitfulness = c(8, 26), grandiosity = c(14, 32),
  irresponsibility = c(3, 21), impulsivity = c(9, 27), distractibility = c(15, 33),
  unusual_beliefs = c(5, 23), eccentricity = c(11, 29), percept_dysreg = c(17, 35),
  perfectionism = c(6, 18), rigidity = c(12, 24), orderliness = c(30, 36)
)
pf_domain_key_bfm <- c(pf_domain_key,
                       list(anankastia = c("perfectionism", "rigidity", "orderliness")))

# Total score: mean of the items of the five DSM-5 domains of a version
# (220 / 100 / 25 / 30 items; Anankastia is not part of it). Normed at table
# level "total", scale "total" (manuscript Draft 20, Supplement S3.3, S5.3).
pf_total_items_bfm <- sort(unlist(pf_facet_key_bfm[setdiff(names(pf_facet_key_bfm),
                                                          c("perfectionism", "rigidity", "orderliness"))]))

pf_instruments <- list(
  full = list(n_items = 220, facets = pf_facet_key_full, domains = pf_domain_key,
              reverse = pf_reverse_full, domain_type = "facet_mean",
              report_facets = TRUE, item_numbering = "full",
              total_items = sort(unlist(pf_facet_key_full)), total_domains = names(pf_domain_key)),
  sf   = list(n_items = 100, facets = pf_facet_key_sf, domains = pf_domain_key,
              reverse = integer(0), domain_type = "facet_mean",
              report_facets = TRUE, item_numbering = "full",
              total_items = sort(unlist(pf_facet_key_sf)), total_domains = names(pf_domain_key)),
  bf   = list(n_items = 25, facets = NULL, domains = pf_domain_key_bf,
              reverse = integer(0), domain_type = "item_mean",
              report_facets = FALSE, item_numbering = "form",
              total_items = 1:25, total_domains = names(pf_domain_key_bf)),
  bfplus_m = list(n_items = 36, facets = pf_facet_key_bfm, domains = pf_domain_key_bfm,
                  reverse = integer(0), domain_type = "facet_mean",
                  report_facets = FALSE, item_numbering = "form",
                  item_mean_domains = "anankastia",
                  total_items = pf_total_items_bfm, total_domains = names(pf_domain_key))
)
stopifnot(length(pf_instruments$full$total_items) == 220, length(pf_instruments$sf$total_items) == 100,
          length(pf_instruments$bfplus_m$total_items) == 30)

pf_age_breaks <- c(18, 35, 50, 65, Inf)
pf_age_labels <- c("[18,35)", "[35,50)", "[50,65)", "[65,Inf)")
pf_thresholds <- c(60, 65, 70)
pf_missing_tolerance <- 0.8   # flag scales with < 80 % of items answered

# -----------------------------------------------------------------------------
# 2. Small helpers
# -----------------------------------------------------------------------------

pf_read_url <- function(base_url, file, reader) {
  path <- if (grepl("^https?://", base_url)) paste0(base_url, file) else file.path(base_url, file)
  reader(path)
}

pf_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, na.strings = c("", "NA"),
                  encoding = "UTF-8", fileEncoding = "UTF-8")
}

pf_read_json <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

pf_read_items <- function(path) {
  d <- utils::read.delim(path, stringsAsFactors = FALSE, quote = "",
                         encoding = "UTF-8", fileEncoding = "UTF-8")
  names(d)[1:2] <- c("item", "text")
  d
}

pf_fmt <- function(template, ...) {
  # simple {key} substitution
  vals <- list(...)
  for (k in names(vals)) template <- gsub(paste0("{", k, "}"), vals[[k]], template, fixed = TRUE)
  template
}

pf_num <- function(x) suppressWarnings(as.numeric(as.character(x)))

pf_esc <- function(x) {
  x <- gsub("&", "&amp;", x); x <- gsub("<", "&lt;", x); gsub(">", "&gt;", x)
}

pf_one <- function(df, col) {
  # first row value of a survey column, or NA
  if (is.null(df) || !is.data.frame(df) || nrow(df) == 0 || !col %in% names(df)) return(NA)
  df[[col]][1]
}

pf_nearest_row <- function(raw_col, value) {
  if (is.na(value) || length(raw_col) == 0) return(NA_integer_)
  which.min(abs(raw_col - value))
}

# -----------------------------------------------------------------------------
# 3. Scoring
# -----------------------------------------------------------------------------

# From item responses. `items` is the survey data frame; responses are coded
# 1..4 by formr (choice keys) and are shifted to 0..3 here.
pf_score_items <- function(items, version) {
  inst <- pf_instruments[[version]]
  cols <- paste0("pid5_", seq_len(inst$n_items))
  if (inst$item_numbering == "full") {
    nums <- sort(unique(unlist(c(inst$facets, if (is.null(inst$facets)) inst$domains))))
    cols <- paste0("pid5_", nums)
  }
  present <- cols[cols %in% names(items)]
  x <- setNames(rep(NA_real_, length(cols)), cols)
  x[present] <- pf_num(unlist(items[1, present]))
  x <- x - 1                                   # 1..4 -> 0..3
  x[!is.na(x) & (x < 0 | x > 3)] <- NA
  if (length(inst$reverse)) {
    rv <- paste0("pid5_", inst$reverse)
    rv <- rv[rv %in% names(x)]
    x[rv] <- 3 - x[rv]
  }
  pf_score_from_vector(x, version, items_available = TRUE)
}

pf_score_from_vector <- function(x, version, items_available) {
  inst <- pf_instruments[[version]]
  get <- function(ids) x[paste0("pid5_", ids)]

  facet_tab <- NULL
  if (!is.null(inst$facets)) {
    facet_tab <- do.call(rbind, lapply(names(inst$facets), function(f) {
      v <- get(inst$facets[[f]])
      data.frame(scale = f, level = "facet", n_items = length(v),
                 n_answered = sum(!is.na(v)),
                 sum = if (any(!is.na(v))) sum(v, na.rm = TRUE) else NA_real_,
                 raw = if (any(!is.na(v))) mean(v, na.rm = TRUE) else NA_real_,
                 stringsAsFactors = FALSE)
    }))
  }

  domain_tab <- do.call(rbind, lapply(names(inst$domains), function(d) {
    comp <- inst$domains[[d]]
    use_item_mean <- inst$domain_type == "item_mean" ||
      (!is.null(inst$item_mean_domains) && d %in% inst$item_mean_domains)
    if (use_item_mean) {
      ids <- if (is.numeric(comp)) comp else unlist(inst$facets[comp])
      v <- get(ids)
      data.frame(scale = d, level = "domain", n_items = length(v),
                 n_answered = sum(!is.na(v)),
                 sum = if (any(!is.na(v))) sum(v, na.rm = TRUE) else NA_real_,
                 raw = if (any(!is.na(v))) mean(v, na.rm = TRUE) else NA_real_,
                 stringsAsFactors = FALSE)
    } else {
      ft <- facet_tab[facet_tab$scale %in% comp, ]
      data.frame(scale = d, level = "domain", n_items = sum(ft$n_items),
                 n_answered = sum(ft$n_answered),
                 sum = if (any(!is.na(ft$sum))) sum(ft$sum, na.rm = TRUE) else NA_real_,
                 raw = if (any(!is.na(ft$raw))) mean(ft$raw, na.rm = TRUE) else NA_real_,
                 stringsAsFactors = FALSE)
    }
  }))

  v <- get(inst$total_items)
  total_tab <- data.frame(scale = "total", level = "total", n_items = length(v),
                          n_answered = sum(!is.na(v)),
                          sum = if (any(!is.na(v))) sum(v, na.rm = TRUE) else NA_real_,
                          raw = if (any(!is.na(v))) mean(v, na.rm = TRUE) else NA_real_,
                          stringsAsFactors = FALSE)

  list(facets = facet_tab, domains = domain_tab, total = total_tab, x = x,
       items_available = items_available)
}

# From entered sum scores. `scores` is the survey data frame with columns
# coding (0 = 0..3, 1 = 1..4), s_<scale> (sum), m_<scale> (items not answered).
# For full/SF the scales are facets, for BF/BF+M the domains.
pf_score_sums <- function(scores, version) {
  inst <- pf_instruments[[version]]
  coding <- pf_num(pf_one(scores, "coding")); if (is.na(coding)) coding <- 0
  entry_level <- if (inst$report_facets) "facet" else "domain"
  keys <- if (entry_level == "facet") inst$facets else inst$domains

  n_of <- function(k) {
    ids <- keys[[k]]
    if (is.numeric(ids)) length(ids) else sum(lengths(inst$facets[ids]))
  }

  tab <- do.call(rbind, lapply(names(keys), function(k) {
    n <- n_of(k)
    s <- pf_num(pf_one(scores, paste0("s_", k)))
    m <- pf_num(pf_one(scores, paste0("m_", k))); if (is.na(m)) m <- 0
    m <- max(0, min(n, round(m)))
    answered <- n - m
    if (!is.na(s) && coding == 1) s <- s - answered
    if (is.na(s) || answered == 0) { s <- NA_real_; raw <- NA_real_ } else {
      s <- max(0, min(3 * answered, s))
      raw <- s / answered
    }
    data.frame(scale = k, level = entry_level, n_items = n, n_answered = answered,
               sum = s, raw = raw, stringsAsFactors = FALSE)
  }))

  total_from <- function(rows) {
    ans <- sum(rows$n_answered); sm <- if (any(!is.na(rows$sum))) sum(rows$sum, na.rm = TRUE) else NA_real_
    data.frame(scale = "total", level = "total", n_items = sum(rows$n_items), n_answered = ans,
               sum = sm, raw = if (is.na(sm) || ans == 0) NA_real_ else sm / ans,
               stringsAsFactors = FALSE)
  }

  if (entry_level == "domain") {
    total_tab <- total_from(tab[tab$scale %in% inst$total_domains, ])
    return(list(facets = NULL, domains = tab, total = total_tab, items_available = FALSE))
  }

  domain_tab <- do.call(rbind, lapply(names(inst$domains), function(d) {
    ft <- tab[tab$scale %in% inst$domains[[d]], ]
    data.frame(scale = d, level = "domain", n_items = sum(ft$n_items),
               n_answered = sum(ft$n_answered),
               sum = if (any(!is.na(ft$sum))) sum(ft$sum, na.rm = TRUE) else NA_real_,
               raw = if (any(!is.na(ft$raw))) mean(ft$raw, na.rm = TRUE) else NA_real_,
               stringsAsFactors = FALSE)
  }))
  total_tab <- total_from(tab)   # all facets of the version
  list(facets = tab, domains = domain_tab, total = total_tab, items_available = FALSE)
}

# -----------------------------------------------------------------------------
# 4. Reference frame and norm lookup
# -----------------------------------------------------------------------------

pf_resolve_frame <- function(intro, texts, cont_available) {
  frame  <- as.character(pf_one(intro, "frame")); if (is.na(frame) || frame == "") frame <- "overall"
  gender <- as.character(pf_one(intro, "gender")); if (is.na(gender)) gender <- ""
  age    <- pf_num(pf_one(intro, "age"))
  notes  <- character(0)
  R <- texts$results

  if (frame != "overall") {
    if (!gender %in% c("m", "f")) {
      notes <- c(notes, R$frame_fallback_gender); frame <- "overall"
    } else if (is.na(age) || age < 18) {
      notes <- c(notes, R$frame_fallback_age); frame <- "overall"
    }
  }
  if (frame == "age" && !cont_available) frame <- "cell"

  age_group <- if (frame != "overall")
    as.character(cut(age, pf_age_breaks, labels = pf_age_labels, right = FALSE)) else NA_character_

  label <- switch(frame,
    overall = R$frame_overall,
    cell    = pf_fmt(R$frame_cell, gender = R$gender_labels[[gender]],
                     age_group = R$age_group_labels[[age_group]]),
    age     = pf_fmt(R$frame_age, gender = R$gender_labels[[gender]], age = age))

  list(frame = frame, gender = if (frame == "overall") "all" else gender,
       age = age, age_group = if (frame == "overall") "all" else age_group,
       label = label, notes = notes)
}

pf_lookup <- function(norms, level, scale, raw, fr) {
  out <- data.frame(T = NA_real_, T_lo = NA_real_, T_hi = NA_real_, pctl = NA_real_,
                    extrap = NA, stringsAsFactors = FALSE)
  if (is.na(raw)) return(out)
  d <- norms[norms$level == level & norms$scale == scale, , drop = FALSE]
  if (fr$frame == "age") {
    ages <- d$age
    a <- min(max(fr$age, min(ages, na.rm = TRUE)), max(ages, na.rm = TRUE))
    d <- d[d$gender == fr$gender & d$age == a, , drop = FALSE]
  } else {
    d <- d[d$gender == fr$gender & d$age_group == fr$age_group, , drop = FALSE]
  }
  if (nrow(d) == 0) return(out)
  i <- pf_nearest_row(d$raw, raw)
  data.frame(T = d$T[i], T_lo = d$T_int_lo[i], T_hi = d$T_int_hi[i],
             pctl = d$pctl_med[i], extrap = as.logical(d$extrapolation[i]),
             stringsAsFactors = FALSE)
}

pf_add_norms <- function(tab, norms, fr) {
  if (is.null(tab)) return(NULL)
  res <- do.call(rbind, lapply(seq_len(nrow(tab)), function(i)
    pf_lookup(norms, tab$level[i], tab$scale[i], tab$raw[i], fr)))
  tab <- cbind(tab, res)
  tab$flag_missing <- !is.na(tab$raw) & tab$n_answered < pf_missing_tolerance * tab$n_items
  tab$flag_none    <- is.na(tab$raw)
  tab$flag_extrap  <- !is.na(tab$extrap) & tab$extrap
  tab
}

# -----------------------------------------------------------------------------
# 5. Main entry point
# -----------------------------------------------------------------------------

pf_run <- function(version, lang, base_url, intro, items = NULL, scores = NULL) {
  stopifnot(version %in% names(pf_instruments))
  inst  <- pf_instruments[[version]]
  texts <- pf_read_url(base_url, paste0("texts_", lang, ".json"), pf_read_json)

  has_items  <- is.data.frame(items)  && nrow(items)  > 0
  has_scores <- is.data.frame(scores) && nrow(scores) > 0
  if (!has_items && !has_scores) {
    return(list(ok = FALSE, texts = texts, message = texts$results$no_results))
  }
  mode <- if (has_items) "items" else "scores"

  norms <- tryCatch(pf_read_url(base_url, paste0("norms_", version, ".csv"), pf_read_csv),
                    error = function(e) NULL)
  if (is.null(norms)) return(list(ok = FALSE, texts = texts, message = texts$results$load_error))

  want_age <- identical(as.character(pf_one(intro, "frame")), "age")
  norms_age <- NULL
  if (want_age) {
    norms_age <- tryCatch(pf_read_url(base_url, paste0("norms_", version, "_age.csv"), pf_read_csv),
                          error = function(e) NULL)
  }
  fr <- pf_resolve_frame(intro, texts, cont_available = !is.null(norms_age))
  use_norms <- if (fr$frame == "age") norms_age else norms

  sc <- if (mode == "items") pf_score_items(items, version) else pf_score_sums(scores, version)
  domains <- pf_add_norms(sc$domains, use_norms, fr)
  total   <- pf_add_norms(sc$total, use_norms, fr)
  facets  <- if (inst$report_facets) pf_add_norms(sc$facets, use_norms, fr) else NULL

  item_texts <- NULL
  if (mode == "items") {
    item_texts <- tryCatch(pf_read_url(base_url, paste0("items_", version, "_", lang, ".tsv"),
                                       pf_read_items), error = function(e) NULL)
  }

  list(ok = TRUE, version = version, lang = lang, inst = inst, texts = texts,
       mode = mode, frame = fr, domains = domains, total = total, facets = facets,
       x = sc$x, item_texts = item_texts)
}

# -----------------------------------------------------------------------------
# 6. Rendering: HTML
# -----------------------------------------------------------------------------

pf_css <- '
<style>
.pf-table {width:100%; border-collapse:collapse; margin-bottom:1em; font-size:95%;}
.pf-table th {text-align:left; border-bottom:2px solid #444; padding:6px 8px; background:#f4f4f4;}
.pf-table td {border-bottom:1px solid #ddd; padding:5px 8px; vertical-align:top;}
.pf-table td.num, .pf-table th.num {text-align:right; white-space:nowrap;}
.pf-table tr.pf-primary td.scale {font-weight:bold;}
.pf-table tr.pf-domain-head td {background:#eef2f7; font-weight:bold; border-top:2px solid #999;}
.pf-table tr.pf-total td {border-top:2px solid #444; background:#f7f7f7; font-weight:bold;}
.pf-note {background:#fff6d6; border-left:4px solid #e0b400; padding:8px 12px; margin:8px 0;}
.pf-info {background:#eef2f7; border-left:4px solid #5c85ff; padding:8px 12px; margin:8px 0;}
.pf-small {font-size:90%; color:#444;}
</style>'

pf_fmt_num <- function(x, digits = 1) ifelse(is.na(x), "\u2013", formatC(x, format = "f", digits = digits))

pf_fmt_pctl <- function(p) {
  if (is.na(p)) return("\u2013")
  v <- round(100 * p)
  if (v >= 100) return("&gt; 99")
  if (v <= 0) return("&lt; 1")
  as.character(v)
}

pf_ci <- function(lo, hi) ifelse(is.na(lo) | is.na(hi), "\u2013",
                                 paste0("[", pf_fmt_num(lo), ", ", pf_fmt_num(hi), "]"))

pf_flags <- function(tab, R) {
  f <- rep("", nrow(tab))
  f <- ifelse(tab$flag_missing, paste0(f, "<sup>", R$flag_missing, "</sup>"), f)
  f <- ifelse(tab$flag_extrap,  paste0(f, "<sup>", R$flag_extrapolated, "</sup>"), f)
  f
}

pf_render_summary <- function(pf) {
  T <- pf$texts
  cat(pf_css)
  cat("<h2>", T$results$heading, "</h2>\n", sep = "")
  if (!isTRUE(pf$ok)) { cat('<div class="pf-note">', pf$message, "</div>\n"); return(invisible()) }
  R <- T$results
  cat("<p>", pf_fmt(R$instrument_line, instrument = T$instruments[[pf$version]],
                    mode = if (pf$mode == "items") R$mode_items else R$mode_scores), "<br>",
      pf_fmt(R$frame_line, frame = pf$frame$label), "</p>\n", sep = "")
  for (n in pf$frame$notes) cat('<div class="pf-note">', n, "</div>\n")
  invisible()
}

pf_table_html <- function(tab, labels, R, primary = NULL, group_heads = NULL, total_rows = NULL) {
  hdr <- c(R$col_scale, R$col_items, R$col_sum, R$col_mean, R$col_T, R$col_ci, R$col_pctl)
  cls <- c("", "num", "num", "num", "num", "num", "num")
  out <- '<table class="pf-table">\n<tr>'
  out <- paste0(out, paste0("<th class=\"", cls, "\">", hdr, "</th>", collapse = ""), "</tr>\n")
  flags <- pf_flags(tab, R)
  for (i in seq_len(nrow(tab))) {
    s <- tab$scale[i]
    if (!is.null(group_heads) && s %in% names(group_heads))
      out <- paste0(out, '<tr class="pf-domain-head"><td colspan="7">', group_heads[[s]], "</td></tr>\n")
    rc <- if (!is.null(primary) && s %in% primary) ' class="pf-primary"' else
          if (!is.null(total_rows) && s %in% total_rows) ' class="pf-total"' else ""
    out <- paste0(out, "<tr", rc, ">",
      '<td class="scale">', labels[[s]], "</td>",
      '<td class="num">', tab$n_answered[i], "/", tab$n_items[i], "</td>",
      '<td class="num">', pf_fmt_num(tab$sum[i], 0), "</td>",
      '<td class="num">', pf_fmt_num(tab$raw[i], 2), "</td>",
      '<td class="num"><b>', pf_fmt_num(tab$T[i]), "</b>", flags[i], "</td>",
      '<td class="num">', pf_ci(tab$T_lo[i], tab$T_hi[i]), "</td>",
      '<td class="num">', pf_fmt_pctl(tab$pctl[i]), "</td>",
      "</tr>\n")
  }
  paste0(out, "</table>\n")
}

pf_render_tables <- function(pf) {
  if (!isTRUE(pf$ok)) return(invisible())
  T <- pf$texts; R <- T$results
  cat("<h3>", R$table_domains_heading, "</h3>\n", sep = "")
  dt <- rbind(pf$domains, pf$total)
  labels <- c(T$domains, list(total = T$total$label))
  cat(pf_table_html(dt, labels, R, total_rows = "total"))
  cat('<p class="pf-small">', T$total$footnote, "</p>\n")
  any_missing <- any(dt$flag_missing); any_extrap <- any(dt$flag_extrap)

  if (!is.null(pf$facets)) {
    cat("<h3>", R$table_facets_heading, "</h3>\n", sep = "")
    order <- unlist(pf_facet_display)
    heads <- list(); primary <- character(0)
    for (d in names(pf_facet_display)) {
      heads[[pf_facet_display[[d]][1]]] <- T$domains[[d]]
      primary <- c(primary, pf$inst$domains[[d]])
    }
    ft <- pf$facets[match(order, pf$facets$scale), ]
    cat(pf_table_html(ft, T$facets, R, primary = primary, group_heads = heads))
    cat('<p class="pf-small">', R$footnote_facets_primary, "</p>\n")
    any_missing <- any_missing || any(ft$flag_missing); any_extrap <- any_extrap || any(ft$flag_extrap)
  } else if (pf$version == "bfplus_m") {
    cat('<p class="pf-small">', R$footnote_bfm, "</p>\n")
  }
  cat('<p class="pf-small">', R$footnote_pctl, "</p>\n")
  if (any_missing) cat('<p class="pf-small">', R$footnote_missing, "</p>\n")
  if (any_extrap)  cat('<p class="pf-small">', R$footnote_extrapolated, "</p>\n")
  invisible()
}

pf_render_notes <- function(pf) {
  if (!isTRUE(pf$ok)) return(invisible())
  R <- pf$texts$results
  cat("<h3>", R$how_to_read_heading, "</h3>\n", '<div class="pf-info">', R$how_to_read, "</div>\n", sep = "")
  cat('<p class="pf-small">Version ', pf_version_tag, "</p>\n", sep = "")
  invisible()
}

pf_render_high_items <- function(pf) {
  if (!isTRUE(pf$ok) || pf$mode != "items" || is.null(pf$item_texts)) return(invisible())
  T <- pf$texts; R <- T$results
  x <- pf$x
  hi <- names(x)[!is.na(x) & x == 3]
  cat("<h3>", R$high_items_heading, "</h3>\n", sep = "")
  if (length(hi) == 0) { cat("<p>", R$high_items_none, "</p>\n"); return(invisible()) }
  cat("<p>", R$high_items_text, "</p>\n")
  nums <- as.integer(sub("pid5_", "", hi))
  # scale membership for display
  inst <- pf$inst
  member <- function(k) {
    if (!is.null(inst$facets)) {
      f <- names(inst$facets)[vapply(inst$facets, function(v) k %in% v, logical(1))]
      if (length(f)) return(if (f[1] %in% names(T$facets)) T$facets[[f[1]]] else f[1])
    }
    d <- names(inst$domains)[vapply(inst$domains, function(v) is.numeric(v) && k %in% v, logical(1))]
    if (length(d)) T$domains[[d[1]]] else ""
  }
  it <- pf$item_texts
  out <- '<table class="pf-table"><tr><th class="num">'
  out <- paste0(out, R$col_item_no, "</th><th>", R$col_item_text, "</th><th>", R$col_item_facet, "</th></tr>\n")
  for (k in sort(nums)) {
    txt <- it$text[match(k, it$item)]
    if (is.na(txt)) txt <- ""
    rev_mark <- if (k %in% inst$reverse) paste0(' <span class="pf-small">(', R$reversed_marker, ")</span>") else ""
    out <- paste0(out, '<tr><td class="num">', k, "</td><td>", pf_esc(txt), rev_mark, "</td><td>", member(k), "</td></tr>\n")
  }
  cat(out, "</table>\n")
  invisible()
}

# -----------------------------------------------------------------------------
# 7. Rendering: figures
# -----------------------------------------------------------------------------

pf_band_colors <- c("#fdf0d5", "#f8c9a0", "#f28e7a")   # mild, moderate, severe

pf_plot_base <- function(p, ymin, ymax, R, horizontal = FALSE) {
  # background bands and reference lines shared by both plots
  b <- pf_thresholds
  add_band <- function(p, from, to, fill) {
    p + ggplot2::annotate("rect", xmin = -Inf, xmax = Inf, ymin = from, ymax = to, fill = fill, alpha = 0.55)
  }
  p <- add_band(p, b[1], b[2], pf_band_colors[1])
  p <- add_band(p, b[2], b[3], pf_band_colors[2])
  p <- add_band(p, b[3], Inf,  pf_band_colors[3])
  p <- p + ggplot2::geom_hline(yintercept = 50, linetype = "dashed", colour = "grey35", linewidth = 0.7) +
    ggplot2::geom_hline(yintercept = b, colour = "grey55", linewidth = 0.3)
  p
}

pf_theme <- function() {
  ggplot2::theme_classic(base_size = 13) +
    ggplot2::theme(axis.title = ggplot2::element_text(face = "bold"),
                   axis.line = ggplot2::element_line(linewidth = 0.6),
                   panel.grid.major.y = ggplot2::element_line(colour = "grey90", linewidth = 0.3),
                   strip.background = ggplot2::element_rect(fill = "#dfe7f2", colour = NA),
                   strip.text = ggplot2::element_text(face = "bold"),
                   legend.position = "top")
}

pf_y_limits <- function(lo, hi) {
  lo <- suppressWarnings(min(20, lo - 3, na.rm = TRUE)); hi <- suppressWarnings(max(80, hi + 3, na.rm = TRUE))
  c(max(0, floor(lo / 5) * 5), min(100, ceiling(hi / 5) * 5))
}

pf_plot_domains <- function(pf) {
  if (!isTRUE(pf$ok)) return(invisible(NULL))
  T <- pf$texts; R <- T$results
  d <- rbind(pf$domains, pf$total)
  n_dom <- nrow(pf$domains)
  lab <- vapply(c(unlist(T$domains[pf$domains$scale]), T$total$label),
                function(z) paste(strwrap(z, width = 14), collapse = "\n"), "")
  d$label <- factor(lab, levels = lab)
  d$is_total <- d$scale == "total"
  d$shape <- ifelse(d$is_total, ifelse(d$flag_missing, 5, 18), ifelse(d$flag_missing, 1, 16))
  d$psize <- ifelse(d$is_total, 5, 3.6)
  lims <- pf_y_limits(c(d$T_lo, d$T), c(d$T_hi, d$T))
  sev <- R$severity_labels
  n <- nrow(d)

  p <- ggplot2::ggplot(d, ggplot2::aes(x = label, y = T))
  p <- pf_plot_base(p, lims[1], lims[2], R)
  p <- p +
    ggplot2::geom_line(data = d[!d$is_total, ], ggplot2::aes(group = 1), colour = "grey50",
                       linewidth = 0.6, na.rm = TRUE) +
    ggplot2::geom_vline(xintercept = n_dom + 0.5, colour = "grey60", linetype = "dotted") +
    ggplot2::geom_linerange(ggplot2::aes(ymin = T_lo, ymax = T_hi), colour = "#1f4e79", linewidth = 2.2,
                            alpha = 0.85, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(shape = shape, size = psize), colour = "black", fill = "white",
                        na.rm = TRUE) +
    ggplot2::scale_shape_identity() + ggplot2::scale_size_identity() +
    ggplot2::annotate("text", x = n + 0.75, y = pf_thresholds + 0.6, label = unlist(sev),
                      hjust = 0, vjust = 0, size = 3.2, colour = "grey30") +
    ggplot2::scale_x_discrete(expand = ggplot2::expansion(add = c(0.6, 1.9))) +
    ggplot2::scale_y_continuous(breaks = seq(0, 100, 10), minor_breaks = NULL) +
    ggplot2::coord_cartesian(ylim = lims, clip = "off") +
    ggplot2::labs(x = NULL, y = R$axis_T, title = T$instruments[[pf$version]],
                  subtitle = pf$frame$label) +
    pf_theme() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(size = 11))
  p
}

pf_plot_facets <- function(pf) {
  if (!isTRUE(pf$ok) || is.null(pf$facets)) return(invisible(NULL))
  T <- pf$texts; R <- T$results
  order <- unlist(pf_facet_display)
  f <- pf$facets[match(order, pf$facets$scale), ]
  f$domain <- factor(rep(unlist(T$domains[names(pf_facet_display)]), lengths(pf_facet_display)),
                     levels = unlist(T$domains[names(pf_facet_display)]))
  f$primary <- f$scale %in% unlist(pf$inst$domains)
  f$label <- factor(unlist(T$facets[f$scale]), levels = rev(unlist(T$facets[f$scale])))
  f$shape <- ifelse(f$primary, ifelse(f$flag_missing, 1, 16), ifelse(f$flag_missing, 0, 15))
  lims <- pf_y_limits(c(f$T_lo, f$T), c(f$T_hi, f$T))

  p <- ggplot2::ggplot(f, ggplot2::aes(x = label, y = T))
  p <- pf_plot_base(p, lims[1], lims[2], R)
  p <- p +
    ggplot2::geom_linerange(ggplot2::aes(ymin = T_lo, ymax = T_hi), colour = "#1f4e79", linewidth = 2,
                            alpha = 0.85, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(shape = shape), size = 3.2, colour = "black", fill = "white",
                        na.rm = TRUE) +
    ggplot2::scale_shape_identity() +
    ggplot2::scale_y_continuous(breaks = seq(0, 100, 10), minor_breaks = NULL) +
    ggplot2::coord_flip(ylim = lims) +
    ggplot2::facet_grid(domain ~ ., scales = "free_y", space = "free_y") +
    ggplot2::labs(x = NULL, y = R$axis_T, title = T$instruments[[pf$version]],
                  subtitle = pf$frame$label) +
    pf_theme() +
    ggplot2::theme(strip.text.y = ggplot2::element_text(angle = 0, hjust = 0),
                   panel.grid.major.y = ggplot2::element_blank(),
                   panel.grid.major.x = ggplot2::element_line(colour = "grey90", linewidth = 0.3),
                   axis.text.y = ggplot2::element_text(size = 10.5))
  p
}
