#!/usr/bin/env bash

# see https://stackoverflow.com/a/246128/5354298
get_script_dir() { echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"; }
SCRIPT_DIR=$(get_script_dir)

out_data_dir="$(pwd)/out"
mkdir -p "$out_data_dir"

db="${1:-pubmed_improved}"

if ! psql -d "$db" -q -c "\d" >/dev/null 2>&1; then
  echo "Database $db does not exist." >/dev/stderr
  exit 1
fi

psql "$db" -c "\copy (SELECT year, COUNT(DISTINCT pmcid) FROM pmcs GROUP BY year) \
  TO '$out_data_dir/pmcid_count_by_year.tsv' DELIMITER E'\t' CSV HEADER"
