#!/usr/bin/env Rscript
# Reproducible analysis. This script requires a real monthly RFB snapshot loaded into PostgreSQL.

required <- c("DBI", "RPostgres", "dplyr", "tidyr", "readr", "ggplot2", "scales",
              "survival", "survminer", "cluster", "factoextra", "lubridate", "broom")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Install required R packages first: ", paste(missing, collapse = ", "))

root <- normalizePath(file.path(dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])), ".."), mustWork = TRUE)
if (file.exists(file.path(root, ".env"))) readRenviron(file.path(root, ".env"))
for (d in c("output/figures", "output/tables")) dir.create(file.path(root, d), recursive = TRUE, showWarnings = FALSE)

con <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("POSTGRES_HOST", "localhost"),
  port = as.integer(Sys.getenv("POSTGRES_PORT", "5432")),
  dbname = Sys.getenv("POSTGRES_DB", "survival_abc"),
  user = Sys.getenv("POSTGRES_USER", "analyst"),
  password = Sys.getenv("POSTGRES_PASSWORD")
)
cohort <- DBI::dbGetQuery(con, "SELECT * FROM analytics.business_cohort ORDER BY cnpj_basic") |>
  dplyr::mutate(
    opened_at = as.Date(opened_at), closed_at = as.Date(closed_at),
    snapshot_date = as.Date(snapshot_date),
    is_closed = as.logical(is_closed), is_mei = as.logical(is_mei), is_simples = as.logical(is_simples),
    capital_social = suppressWarnings(as.numeric(capital_social)),
    cnae_division = dplyr::if_else(is.na(cnae_division) | cnae_division == "", "Unknown", cnae_division),
    company_size = factor(company_size, levels = c("ME", "EPP")),
    mei_group = dplyr::case_when(is_mei %in% TRUE ~ "MEI", is_mei %in% FALSE ~ "Não MEI", TRUE ~ "Não informado"),
    sector_group = cnae_division
  )
if (nrow(cohort) == 0) stop("The analysis-ready cohort is empty. Check municipality mapping and the loaded snapshot; no results were fabricated.")
if (anyDuplicated(cohort$cnpj_basic)) stop("Cohort violates the one-row-per-CNPJ-basic contract.")

snapshot_date <- max(cohort$snapshot_date, na.rm = TRUE)
if (!is.finite(as.numeric(snapshot_date))) stop("No valid snapshot_date was loaded.")

# Data-quality checks are explicit and are not silently repaired into events.
valid_open <- !is.na(cohort$opened_at) & cohort$opened_at <= snapshot_date
valid_close <- is.na(cohort$closed_at) | cohort$closed_at >= cohort$opened_at
closed_missing_date <- (cohort$registration_status_code == '08' & is.na(cohort$closed_at)) %in% TRUE
closed_after_snapshot <- (cohort$registration_status_code == '08' &
  !is.na(cohort$registration_status_date) & cohort$registration_status_date > snapshot_date) %in% TRUE
quality <- tibble::tibble(
  check = c("cohort_rows", "distinct_cnpj_basic", "duplicate_cnpj_basic", "missing_opening_date",
            "opening_date_after_snapshot", "missing_primary_cnae", "closed_status_without_valid_date",
            "closure_before_opening", "closure_date_after_snapshot", "missing_registration_status",
            "missing_capital_social", "mei_unknown", "municipalities_in_cohort"),
  value = c(nrow(cohort), dplyr::n_distinct(cohort$cnpj_basic), sum(duplicated(cohort$cnpj_basic)),
            sum(is.na(cohort$opened_at)), sum(!is.na(cohort$opened_at) & cohort$opened_at > snapshot_date),
            sum(is.na(cohort$primary_cnae_code) | cohort$primary_cnae_code == ""), sum(closed_missing_date %in% TRUE),
            sum(!is.na(cohort$closed_at) & !is.na(cohort$opened_at) & cohort$closed_at < cohort$opened_at),
            sum(closed_after_snapshot),
            sum(is.na(cohort$registration_status_code) | trimws(cohort$registration_status_code) == ""),
            sum(is.na(cohort$capital_social)), sum(is.na(cohort$is_mei)), dplyr::n_distinct(cohort$municipality))
)
readr::write_csv(quality, file.path(root, "output/tables/data_quality.csv"))

analysis <- cohort |>
  dplyr::filter(valid_open, valid_close, !closed_after_snapshot, !closed_missing_date) |>
  dplyr::mutate(
    event = is_closed %in% TRUE,
    end_at = dplyr::if_else(event, closed_at, snapshot_date),
    duration_days = as.numeric(end_at - opened_at),
    duration_years = duration_days / 365.25,
    cnae_division = factor(cnae_division),
    log_capital = ifelse(is.na(capital_social), NA_real_, log1p(pmax(capital_social, 0)))
  ) |>
  dplyr::filter(is.finite(duration_days), duration_days >= 0)
if (nrow(analysis) == 0) stop("No records remain after date-quality rules; inspect output/tables/data_quality.csv.")

# Keep the eight largest CNAE divisions as distinct Cox/KM strata; pool the tail.
top_sectors <- analysis |> dplyr::count(cnae_division, sort = TRUE) |> dplyr::slice_head(n = 8) |> dplyr::pull(cnae_division) |> as.character()
analysis <- analysis |> dplyr::mutate(sector_group = ifelse(as.character(cnae_division) %in% top_sectors,
                                                            as.character(cnae_division), "Other"),
                                      sector_group = factor(sector_group))

# Descriptive counts and regional comparisons.
openings <- analysis |> dplyr::count(year = lubridate::year(opened_at), name = "openings") |> dplyr::arrange(year)
closures <- analysis |> dplyr::filter(event) |> dplyr::count(year = lubridate::year(closed_at), name = "closures") |> dplyr::arrange(year)
annual <- dplyr::full_join(openings, closures, by = "year") |> dplyr::mutate(dplyr::across(c(openings, closures), ~ tidyr::replace_na(.x, 0L))) |> dplyr::arrange(year)
readr::write_csv(annual, file.path(root, "output/tables/annual_openings_closures.csv"))
city_summary <- analysis |> dplyr::group_by(municipality) |> dplyr::summarise(
  businesses = dplyr::n(), closed_at_snapshot = sum(event), closure_share = mean(event),
  mei_share = mean(is_mei, na.rm = TRUE), median_age_years = median(duration_years),
  mean_capital = mean(capital_social, na.rm = TRUE), .groups = "drop"
) |> dplyr::arrange(dplyr::desc(businesses))
readr::write_csv(city_summary, file.path(root, "output/tables/municipality_summary.csv"))
sector_summary <- analysis |> dplyr::group_by(cnae_division, .drop = FALSE) |> dplyr::summarise(
  businesses = dplyr::n(), closed_at_snapshot = sum(event), closure_share = mean(event),
  mei_share = mean(is_mei, na.rm = TRUE), median_age_years = median(duration_years),
  mean_capital = mean(capital_social, na.rm = TRUE), .groups = "drop"
) |> dplyr::filter(businesses > 0) |> dplyr::arrange(dplyr::desc(businesses))
readr::write_csv(sector_summary, file.path(root, "output/tables/sector_summary.csv"))

p_annual <- ggplot2::ggplot(annual, ggplot2::aes(x = year)) +
  ggplot2::geom_line(ggplot2::aes(y = openings, colour = "Aberturas"), linewidth = 0.8, na.rm = TRUE) +
  ggplot2::geom_line(ggplot2::aes(y = closures, colour = "Baixas"), linewidth = 0.8, na.rm = TRUE) +
  ggplot2::scale_colour_manual(values = c("Aberturas" = "#2463A6", "Baixas" = "#C24A3A"), name = NULL) +
  ggplot2::labs(title = "Aberturas e baixas por ano", subtitle = paste("Matrizes MPE no ABC; referência:", snapshot_date), x = "Ano", y = "Registros") +
  ggplot2::theme_minimal(base_size = 12) + ggplot2::theme(legend.position = "bottom")
ggplot2::ggsave(file.path(root, "output/figures/openings_closures_by_year.png"), p_annual, width = 9, height = 5, dpi = 160)

p_city <- ggplot2::ggplot(city_summary, ggplot2::aes(x = reorder(municipality, businesses), y = businesses)) +
  ggplot2::geom_col(fill = "#2463A6") + ggplot2::coord_flip() +
  ggplot2::labs(title = "Matrizes MPE por município", x = NULL, y = "Empresas") + ggplot2::theme_minimal(base_size = 12)
ggplot2::ggsave(file.path(root, "output/figures/businesses_by_municipality.png"), p_city, width = 9, height = 5, dpi = 160)

# Kaplan-Meier. A baixa administrativa is the event proxy, not business failure.
km_data <- analysis |> dplyr::filter(duration_days > 0, !is.na(is_mei))
if (nrow(km_data) > 0 && sum(km_data$event) > 0) {
  fit_mei <- survival::survfit(survival::Surv(duration_days, event) ~ mei_group, data = km_data)
  km_mei <- survminer::ggsurvplot(fit_mei, data = km_data, conf.int = TRUE, risk.table = FALSE,
    censor = TRUE, legend.title = "Regime", xlab = "Dias desde a abertura", ylab = "Probabilidade de permanecer sem baixa",
    title = "Kaplan–Meier por condição de MEI", ggtheme = ggplot2::theme_minimal(base_size = 12))
  ggplot2::ggsave(file.path(root, "output/figures/survival_by_mei.png"), km_mei$plot, width = 9, height = 5.5, dpi = 160)
  sector_km <- km_data |> dplyr::filter(sector_group != "Other")
  if (dplyr::n_distinct(sector_km$sector_group) >= 2) {
    fit_sector <- survival::survfit(survival::Surv(duration_days, event) ~ sector_group, data = sector_km)
    km_sector <- survminer::ggsurvplot(fit_sector, data = sector_km, conf.int = FALSE, risk.table = FALSE,
      censor = FALSE, legend.title = "Divisão CNAE (2 dígitos)", xlab = "Dias desde a abertura", ylab = "Probabilidade de permanecer sem baixa",
      title = "Kaplan–Meier por principais divisões CNAE", ggtheme = ggplot2::theme_minimal(base_size = 12))
    ggplot2::ggsave(file.path(root, "output/figures/survival_by_sector.png"), km_sector$plot, width = 10, height = 6, dpi = 160)
  }
}

# Cox proportional-hazards regression. Unknown MEI status is excluded, not relabelled.
cox_data <- analysis |> dplyr::filter(duration_days > 0, !is.na(is_mei), !is.na(company_size)) |>
  dplyr::mutate(mei_group = factor(ifelse(is_mei, "MEI", "Não MEI")), municipality = factor(municipality))
cox_table <- tibble::tibble()
if (sum(cox_data$event) >= 10 && nrow(cox_data) > 20) {
  cox_candidates <- c("sector_group", "mei_group", "municipality", "company_size", "log_capital")
  cox_predictors <- cox_candidates[vapply(cox_candidates, function(nm) dplyr::n_distinct(cox_data[[nm]], na.rm = TRUE) > 1, logical(1))]
  cox_rhs <- if (length(cox_predictors)) paste(cox_predictors, collapse = " + ") else "1"
  cox_formula <- stats::as.formula(paste("survival::Surv(duration_days, event) ~", cox_rhs))
  cox_fit <- survival::coxph(cox_formula, data = cox_data, ties = "efron", x = TRUE)
  cox_table <- broom::tidy(cox_fit, exponentiate = TRUE, conf.int = TRUE) |>
    dplyr::transmute(term, hazard_ratio = estimate, conf_low = conf.low, conf_high = conf.high, p_value = p.value)
  readr::write_csv(cox_table, file.path(root, "output/tables/cox_hazard_ratios.csv"))
  cox_diag <- survival::cox.zph(cox_fit)
  utils::capture.output(print(cox_diag), file = file.path(root, "output/tables/cox_ph_assumption.txt"))
} else {
  writeLines("Cox model not estimated: require at least 10 observed events and 20 usable records. This is a stability guard, not evidence of no effect.",
             file.path(root, "output/tables/cox_hazard_ratios_not_estimated.txt"))
}

# Two-year binary endpoint: only businesses with a full 730-day observation window enter.
horizon <- 730
mature <- analysis |> dplyr::filter(opened_at <= snapshot_date - horizon, !is.na(is_mei), !is.na(company_size)) |>
  dplyr::mutate(closed_within_2y = as.integer(event & closed_at <= opened_at + horizon),
                mei_group = factor(ifelse(is_mei, "MEI", "Não MEI")), municipality = factor(municipality))
logit_table <- tibble::tibble()
if (nrow(mature) > 20 && dplyr::n_distinct(mature$closed_within_2y) == 2) {
  logit_candidates <- c("sector_group", "mei_group", "municipality", "company_size", "log_capital")
  logit_predictors <- logit_candidates[vapply(logit_candidates, function(nm) dplyr::n_distinct(mature[[nm]], na.rm = TRUE) > 1, logical(1))]
  logit_formula <- stats::reformulate(logit_predictors, response = "closed_within_2y")
  logit_fit <- stats::glm(logit_formula, data = mature, family = stats::binomial())
  logit_table <- broom::tidy(logit_fit) |>
    dplyr::mutate(odds_ratio = exp(estimate), conf_low = exp(estimate - 1.96 * std.error),
                  conf_high = exp(estimate + 1.96 * std.error)) |>
    dplyr::transmute(term, odds_ratio, conf_low, conf_high, p_value = p.value)
  readr::write_csv(logit_table, file.path(root, "output/tables/logistic_2y_odds_ratios.csv"))
} else {
  writeLines("Logistic model not estimated: the fully observed 730-day cohort must contain at least 20 records and both outcome classes.",
             file.path(root, "output/tables/logistic_2y_not_estimated.txt"))
}

# Sector clustering: division-level aggregates, standardized measures, elbow + silhouette.
sector_cluster <- analysis |> dplyr::mutate(mature_2y = opened_at <= snapshot_date - horizon,
  closed_2y = mature_2y & event & closed_at <= opened_at + horizon) |>
  dplyr::group_by(cnae_division) |> dplyr::summarise(
    n = dplyr::n(), mei_share = mean(is_mei, na.rm = TRUE),
    closure_rate_2y = if (sum(mature_2y, na.rm = TRUE) > 0) mean(closed_2y[mature_2y], na.rm = TRUE) else NA_real_,
    mean_age_years = mean(duration_years, na.rm = TRUE),
    mean_capital = mean(capital_social, na.rm = TRUE), .groups = "drop") |>
  dplyr::filter(n >= 30, dplyr::if_all(c(mei_share, closure_rate_2y, mean_age_years, mean_capital), is.finite))
if (nrow(sector_cluster) >= 4) {
  features <- c("mei_share", "closure_rate_2y", "mean_age_years", "mean_capital")
  # Capital is heavily right-skewed; standardize log1p(mean capital), not raw BRL.
  cluster_frame <- sector_cluster |> dplyr::mutate(log_mean_capital = log1p(pmax(mean_capital, 0))) |>
    dplyr::select(mei_share, closure_rate_2y, mean_age_years, log_mean_capital) |> as.data.frame()
  feature_sd <- vapply(cluster_frame, stats::sd, numeric(1), na.rm = TRUE)
  cluster_frame <- cluster_frame[, is.finite(feature_sd) & feature_sd > 0, drop = FALSE]
  if (ncol(cluster_frame) < 2) {
    writeLines("Clustering not estimated: fewer than two non-constant features remain; no artificial variation was added.",
               file.path(root, "output/tables/clustering_not_estimated.txt"))
  } else {
  cluster_matrix <- scale(cluster_frame)
  ks <- 2:min(6, nrow(sector_cluster) - 1)
  set.seed(20260928)
  score_rows <- lapply(ks, function(k) {
    fit <- stats::kmeans(cluster_matrix, centers = k, nstart = 50, iter.max = 100)
    sil <- cluster::silhouette(fit$cluster, stats::dist(cluster_matrix))
    data.frame(k = k, total_withinss = fit$tot.withinss, mean_silhouette = mean(sil[, "sil_width"]))
  })
  cluster_scores <- dplyr::bind_rows(score_rows)
  readr::write_csv(cluster_scores, file.path(root, "output/tables/cluster_k_diagnostics.csv"))
  best_k <- cluster_scores$k[which.max(cluster_scores$mean_silhouette)]
  set.seed(20260928)
  km_final <- stats::kmeans(cluster_matrix, centers = best_k, nstart = 100, iter.max = 100)
  hc <- stats::hclust(stats::dist(cluster_matrix), method = "ward.D2")
  sector_cluster$kmeans_cluster <- factor(km_final$cluster)
  sector_cluster$hierarchical_cluster <- factor(stats::cutree(hc, k = best_k))
  readr::write_csv(sector_cluster, file.path(root, "output/tables/sector_clusters.csv"))
  p_elbow <- ggplot2::ggplot(cluster_scores, ggplot2::aes(k, total_withinss)) + ggplot2::geom_line() + ggplot2::geom_point(size = 2) +
    ggplot2::labs(title = "Diagnóstico do cotovelo", x = "k", y = "Soma de quadrados intragrupo") + ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file.path(root, "output/figures/clustering_elbow.png"), p_elbow, width = 7, height = 4.5, dpi = 160)
  p_sil <- ggplot2::ggplot(cluster_scores, ggplot2::aes(k, mean_silhouette)) + ggplot2::geom_line() + ggplot2::geom_point(size = 2) +
    ggplot2::labs(title = "Escolha de k pelo índice de silhueta", x = "k", y = "Silhueta média") + ggplot2::theme_minimal(base_size = 12)
  ggplot2::ggsave(file.path(root, "output/figures/clustering_silhouette.png"), p_sil, width = 7, height = 4.5, dpi = 160)
  p_dend <- factoextra::fviz_dend(hc, k = best_k, rect = TRUE, cex = 0.65, main = "Agrupamento hierárquico (Ward.D2)")
  ggplot2::ggsave(file.path(root, "output/figures/clustering_dendrogram.png"), p_dend, width = 10, height = 6, dpi = 160)
  }
} else {
  writeLines("Clustering not estimated: fewer than four CNAE divisions met the minimum of 30 observations and complete-feature rules.",
             file.path(root, "output/tables/clustering_not_estimated.txt"))
}

# Persist compact, non-identifying tables for the report. Raw company IDs are not exported.
summary_metrics <- tibble::tibble(
  metric = c("snapshot_date", "mpe_head_offices", "observed_admin_closures", "admin_closure_share",
             "mei_share_among_known", "median_observed_duration_years", "mature_2y_cohort_n", "mature_2y_closures"),
  value = c(as.character(snapshot_date), as.character(nrow(analysis)), as.character(sum(analysis$event)),
            as.character(mean(analysis$event)), as.character(mean(analysis$is_mei, na.rm = TRUE)),
            as.character(stats::median(analysis$duration_years)), as.character(nrow(mature)),
            as.character(sum(mature$closed_within_2y)))
)
readr::write_csv(summary_metrics, file.path(root, "output/tables/summary_metrics.csv"))
message("Analysis complete. Snapshot: ", snapshot_date, "; usable cohort: ", nrow(analysis),
        ". Outputs are real-snapshot dependent and contain no simulated observations.")
