# run_local_test.R
# Knits the results pages of the generated runs locally with mock survey data,
# using the local assets folder instead of the hosted base URL.
#   Rscript test/run_local_test.R [lang] [version] [mode] [frame]
# Writes test/out/<lang>_<version>_<mode>_<frame>.html

suppressPackageStartupMessages({ library(jsonlite); library(knitr); library(rmarkdown) })
args <- commandArgs(trailingOnly = TRUE)
lang    <- if (length(args) >= 1) args[1] else "de"
version <- if (length(args) >= 2) args[2] else "full"
mode    <- if (length(args) >= 3) args[3] else "items"     # items | scores
frame   <- if (length(args) >= 4) args[4] else "cell"      # overall | cell | age
gender  <- if (length(args) >= 5) args[5] else "f"
age     <- if (length(args) >= 6) as.numeric(args[6]) else 29



root   <- normalizePath(".")
assets <- file.path(root, "assets")
cfg    <- fromJSON(file.path(root, "build/config.json"))
run    <- fromJSON(file.path(root, "dist", paste0(cfg$runs[[lang]]$run_name, ".json")), simplifyVector = FALSE)
prefix <- cfg$runs[[lang]]$survey_prefix

pos_end <- c(full = 80, sf = 82, bfplus_m = 84, bf = 86)
ep <- Filter(function(u) u$type == "Endpage" && u$position == pos_end[[version]], run$units)[[1]]
body <- gsub(cfg$base_url, paste0(assets, "/"), ep$body, fixed = TRUE)

source(file.path(assets, "pid5_platform.R"))
inst <- pf_instruments[[version]]
set.seed(1)

# ---- mock survey data frames, named as formr would name them ---------------
intro <- data.frame(instrument = c(full = 1, sf = 2, bfplus_m = 3, bf = 4)[[version]],
                    mode = if (mode == "items") 2 else 1, frame = frame,
                    age = if (frame == "overall") NA else age,
                    gender = if (frame == "overall") NA else gender, stringsAsFactors = FALSE)
assign(paste0(prefix, "_intro"), intro)

if (mode == "items") {
  cols <- if (inst$item_numbering == "full")
    paste0("pid5_", sort(unique(unlist(inst$facets)))) else paste0("pid5_", seq_len(inst$n_items))
  # elevated profile: mostly 2s and 3s on some scales, a few missing
  resp <- sample(1:4, length(cols), replace = TRUE, prob = c(0.35, 0.3, 0.2, 0.15))
  resp[sample(length(cols), max(1, round(0.04 * length(cols))))] <- NA
  items <- as.data.frame(as.list(setNames(resp, cols)))
  # make one whole scale mostly missing to test the flag
  if (!is.null(inst$facets)) {
    miss <- paste0("pid5_", inst$facets[[1]]); items[, miss[seq_len(length(miss) - 1)]] <- NA
  }
  assign(paste0(prefix, "_items_", version), items)
} else {
  level <- if (inst$report_facets) "facet" else "domain"
  keys <- if (level == "facet") inst$facets else inst$domains
  n_of <- function(k) { ids <- keys[[k]]; if (is.numeric(ids)) length(ids) else sum(lengths(inst$facets[ids])) }
  sc <- list(coding = 1)   # test the 1..4 coding path
  for (k in names(keys)) {
    n <- n_of(k); m <- if (k == names(keys)[2]) 2 else 0
    sc[[paste0("s_", k)]] <- round(runif(1, 1.2, 3.6) * (n - m))   # 1..4 coded sums
    sc[[paste0("m_", k)]] <- m
  }
  scores <- as.data.frame(sc)
  assign(paste0(prefix, "_scores_", version), scores)
}

dir.create(file.path(root, "test/out"), showWarnings = FALSE, recursive = TRUE)
rmd <- file.path(root, "test/out", sprintf("%s_%s_%s_%s.Rmd", lang, version, mode, frame))
writeLines(c("---", "output: html_document", "---", "", body), rmd)
out <- render(rmd, output_format = html_document(self_contained = TRUE), quiet = TRUE,
              envir = globalenv())
cat("rendered:", out, "\n")
