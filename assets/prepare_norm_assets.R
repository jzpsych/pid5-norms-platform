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
#         assets/norms_<version>_age.csv  (continuous-age norms, if input given)
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
  cont <- read.csv(in_cont, stringsAsFactors = FALSE)
  # The continuous table is expected to carry an integer 'age' column
  # instead of 'age_group'. Adjust here if the column is named differently.
  if (!"age" %in% names(cont))
    stop("Continuous table: no 'age' column found. Columns: ",
         paste(names(cont), collapse = ", "))
  write_split(reduce(cont, "age"), "age", "_age")
} else {
  cat("No continuous-age table found at", in_cont, "(skipped)\n")
}
