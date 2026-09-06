# prepare_norm_assets.R
# Reduces the pipeline norm tables to the columns the scoring platform needs
# and splits them by instrument version, so that each results page loads only
# its own (small) file.
#
# Usage (from the platform project root):
#   Rscript assets/prepare_norm_assets.R <norm_tables_long.csv> \
#           [<norm_tables_age_continuous.csv>] [<output dir>]
#
# Input:  norm_tables_long.csv            (pipeline stage X1, 26,046 rows)
#         norm_tables_age_continuous.csv  (optional; continuous-age tables)
# Output: assets/norms_<version>.csv      (age-band and overall norms)
#         assets/norms_<version>_age.rds  (continuous-age norms, if input given)
#
# Kept columns: version, level, scale, gender, age_group (or age), raw, T,
# T_int_lo, T_int_hi, pctl_med, extrapolation. T values are rounded to one
# decimal, percentiles to four decimals. The platform reports the
# observed-score percentile T and the fully integrated 95% credible interval
# (T_int_lo, T_int_hi), as recommended in the manuscript (Discussion).
# Missing gender / age_group (overall tables) are written as "all".

args    <- commandArgs(trailingOnly = TRUE)
in_long <- if (length(args) >= 1) args[1] else "norm_tables_long.csv"
in_cont <- if (length(args) >= 2) args[2] else "norm_tables_age_continuous.csv"
out_dir <- if (length(args) >= 3) args[3] else "assets"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

keep_cols <- c("raw", "T", "T_int_lo", "T_int_hi", "pctl_med", "extrapolation")

reduce <- function(d, age_col) {
  need <- c("version", "level", "scale", "gender", age_col, keep_cols)
  miss <- setdiff(need, names(d))
  if (length(miss)) stop("Missing columns: ", paste(miss, collapse = ", "))
  d <- d[, need]
  d$T        <- round(d$T, 1)
  d$T_int_lo <- round(d$T_int_lo, 1)
  d$T_int_hi <- round(d$T_int_hi, 1)
  d$pctl_med <- round(d$pctl_med, 4)
  d$raw      <- round(d$raw, 4)
  d$gender   <- ifelse(is.na(d$gender) | d$gender == "", "all", as.character(d$gender))
  if (age_col == "age_group") {
    d$age_group <- ifelse(is.na(d$age_group) | d$age_group == "", "all",
                          as.character(d$age_group))
  }
  d$extrapolation <- as.integer(as.logical(d$extrapolation))
  d
}

write_split <- function(d, age_col, suffix) {
  for (v in sort(unique(d$version))) {
    dv <- d[d$version == v, ]
    dv <- dv[order(dv$level, dv$scale, dv$gender, dv[[age_col]], dv$raw), ]
    f <- file.path(out_dir, sprintf("norms_%s%s.csv", v, suffix))
    write.csv(dv, f, row.names = FALSE, quote = TRUE, na = "")
    cat(sprintf("%-32s %6d rows  %5.2f MB\n", basename(f), nrow(dv),
                file.size(f) / 1e6))
  }
}

long <- read.csv(in_long, stringsAsFactors = FALSE)
stopifnot(all(c("T_int_lo", "T_int_hi") %in% names(long)))
write_split(reduce(long, "age_group"), "age_group", "")

if (file.exists(in_cont)) {
  # Continuous-age tables (pipeline stage M3b, export norm_tables_age_continuous.csv):
  # one row per version x scale x gender x age (18..85) x raw. They carry the
  # norm band (T_lo, T_hi) but, unless the pipeline is extended, no integrated
  # individual interval. The platform uses T_int_lo/T_int_hi if present and
  # otherwise transfers the interval of the gender x age-band cell (see
  # pf_lookup() in pid5_platform.R). Written as .rds because the CSV would be
  # about 25 MB for the full PID-5 and is loaded on every page view.
  cont <- read.csv(in_cont, stringsAsFactors = FALSE)
  need <- c("version", "level", "scale", "gender", "age", "raw", "T", "pctl_med", "extrapolation")
  miss <- setdiff(need, names(cont))
  if (length(miss)) stop("Continuous table: missing columns: ", paste(miss, collapse = ", "),
                         ". Columns found: ", paste(names(cont), collapse = ", "))
  has_int <- all(c("T_int_lo", "T_int_hi") %in% names(cont))
  keep <- c(need, if (has_int) c("T_int_lo", "T_int_hi"), intersect("half_width", names(cont)))
  cont <- cont[, keep]
  cont$T <- round(cont$T, 1); cont$pctl_med <- round(cont$pctl_med, 4); cont$raw <- round(cont$raw, 4)
  if (has_int) { cont$T_int_lo <- round(cont$T_int_lo, 1); cont$T_int_hi <- round(cont$T_int_hi, 1) }
  cont$extrapolation <- as.integer(as.logical(cont$extrapolation))
  cont$age <- as.integer(cont$age)
  for (v in sort(unique(cont$version))) {
    dv <- cont[cont$version == v, ]
    dv <- dv[order(dv$level, dv$scale, dv$gender, dv$age, dv$raw), ]
    rownames(dv) <- NULL
    f <- file.path(out_dir, sprintf("norms_%s_age.rds", v))
    saveRDS(dv, f, compress = "xz")
    cat(sprintf("%-32s %7d rows  %5.2f MB  integrated intervals: %s\n", basename(f), nrow(dv),
                file.size(f) / 1e6, if (has_int) "yes" else "no (platform transfers the band-cell interval)"))
  }
} else {
  cat("No continuous-age table found at", in_cont, "(skipped)\n")
}
