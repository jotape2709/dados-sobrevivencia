SHELL := /usr/bin/env bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
-include .env
export

.PHONY: help download db-up db-down load analyze report all test clean
help:
	@printf '%s\n' 'Targets: download, db-up, db-down, load, analyze, report, all, test, clean' \
	  '  all: download -> start PostgreSQL -> load -> analyze -> render the PDF report' \
	  '  clean: removes generated local data/results (asks for confirmation)'

download:
	bash scripts/download.sh

db-up:
	docker compose up -d db

db-down:
	docker compose down

load:
	bash scripts/load_postgres.sh

analyze:
	Rscript R/01_analysis.R

report:
	Rscript -e "rmarkdown::render('R/02_report.Rmd', output_file='report.pdf', output_dir='output', quiet=TRUE)"

all: download db-up load analyze report

test:
	python3 -m unittest discover -s tests -v
	bash -n scripts/download.sh && bash -n scripts/load_postgres.sh

clean:
	@echo 'This removes downloaded source archives, extracted raw data, and generated outputs; PostgreSQL volume is preserved.'
	@read -r -p 'Type DELETE to continue: ' answer; [[ "$$answer" == DELETE ]]
	rm -rf data/raw/* data/extracted/* output/figures/* output/tables/* output/report.pdf
