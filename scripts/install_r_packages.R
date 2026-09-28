packages <- c("DBI", "RPostgres", "dplyr", "tidyr", "readr", "ggplot2", "scales",
              "survival", "survminer", "cluster", "factoextra", "lubridate", "broom",
              "rmarkdown", "knitr", "tinytex")
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
if (!requireNamespace("tinytex", quietly = TRUE)) stop("tinytex package installation failed")
if (!tinytex::is_tinytex()) tinytex::install_tinytex()
message("R dependencies are ready. If LaTeX install fails on your OS, install TeX Live or TinyTeX manually.")
