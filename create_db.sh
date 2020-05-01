#!/usr/bin/env bash

# see https://stackoverflow.com/a/246128/5354298
get_script_dir() { echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"; }
SCRIPT_DIR=$(get_script_dir)
PWD="$(pwd)"

# Based on http://linuxcommand.org/lc3_wss0140.php
# and https://codeinthehole.com/tips/bash-error-reporting/
PROGNAME=$(basename "$0")

cleanup_complete=0

cleanup() {
  cd "$PWD" || echo "Failed to return to '$PWD'"
  cleanup_complete=1
}

error_exit() {
  #	----------------------------------------------------------------
  #	Function for exit due to fatal program error
  #		Accepts 1 argument:
  #			string containing descriptive error message
  #	----------------------------------------------------------------

  read -r line file <<<"$(caller)"
  echo "" 1>&2
  echo "ERROR: file $file, line $line" 1>&2
  if [ ! "$1" ]; then
    sed "${line}q;d" "$file" 1>&2
  else
    echo "${1:-"Unknown Error"}" 1>&2
  fi
  echo "" 1>&2

  # TODO: should error_exit call cleanup?
  #       The EXIT trap already calls cleanup, so
  #       calling it here means calling it twice.
  if [ ! $cleanup_complete ]; then
    cleanup
  fi
  exit 1
}

trap error_exit ERR
trap cleanup EXIT INT QUIT TERM

# see download.sh
pubmed_data_dir="$(pwd)/tmp"

db="${1:-pubmed}"

if psql -d "$db" -q -c "\d" >/dev/null 2>&1; then
  echo "Database $db already exists." >/dev/stderr
  #psql -c "DROP DATABASE $db;"
  exit 1
fi

echo "Creating database $db..."
psql -c "CREATE DATABASE $db;"

echo "Creating tables..."
psql "$db" -c "\i '$SCRIPT_DIR/create_tables.sql'"

# We need to load the data without the constraints first, because it's messy.
# I'm calling these tables '..._raw'.

echo "Loading pmcs..."
psql "$db" -c "CREATE TABLE pmcs_raw AS \
              TABLE pmcs \
              WITH NO DATA;"
psql "$db" -c "\copy pmcs_raw( \
                journal,issn,eissn,year,volume,issue,page,doi,\
                pmcid,pmid,manuscript_id,release_date \
              ) \
              FROM STDIN DELIMITER ',' CSV HEADER;" \
              <"$pubmed_data_dir/PMC-ids.csv"

echo "Loading organism..."
# By default, the info from taxdump.tar.gz is a collection of data from different sources.
# The following code creates a table 'organisms' with just organism_id and scientific_name,
# and another table 'organism_names' with the full info from taxdump.tar.gz.

psql "$db" -c "CREATE TABLE organism_names_raw AS \
              TABLE organism_names \
              WITH NO DATA;"
# These files don't quote any fields, so we give PostgreSQL a dummy value
# of '\r' for the quote character, which doesn't exist in these files.
# Otherwise, PostgreSQL would import the following rows as duplicates:
#10663     "T4-like viruses"               equivalent name
#10663     T4-like viruses         equivalent name
if grep -q $'\r' "$pubmed_data_dir/taxonomy/names.dmp.tsv"; then
  echo "file includes carriage return(s), so cannot use as quote character." >/dev/stderr
  exit 1
fi
psql "$db" -c "\copy organism_names_raw(organism_id,name,unique_name,name_class) \
              FROM STDIN DELIMITER E'\t' CSV HEADER QUOTE E'\r';" \
              <"$pubmed_data_dir/taxonomy/names.dmp.tsv"

psql "$db" -c "CREATE TABLE merged_organisms( \
                PRIMARY KEY (old_organism_id, new_organism_id), \
                old_organism_id integer, \
                new_organism_id integer \
              );"

psql "$db" -c "\copy merged_organisms(old_organism_id,new_organism_id) \
              FROM STDIN DELIMITER E'\t' CSV HEADER;" \
              <"$pubmed_data_dir/taxonomy/merged.dmp.tsv"

echo "Loading gene2pubmed..."

psql "$db" -c "CREATE TABLE gene2pubmed_raw AS \
              TABLE gene2pubmed \
              WITH NO DATA;"
#tax_id GeneID  PubMed_ID
psql "$db" -c "\copy gene2pubmed_raw(organism_id,gene_id,pmid) \
              FROM STDIN DELIMITER E'\t' CSV HEADER;" \
              <"$pubmed_data_dir/gene2pubmed.tsv"

echo "Loading pubtator data..."

psql "$db" -c "CREATE TABLE gene2pubtator_raw AS \
              TABLE gene2pubtator \
              WITH NO DATA;"
# These files don't quote any fields, so we give PostgreSQL a dummy value
# of '\r' for the quote character, which doesn't exist in these files.
if grep -q $'\r' "$pubmed_data_dir/gene2pubtator_long.tsv"; then
  echo "file includes carriage return(s), so cannot use as quote character." >/dev/stderr
  exit 1
fi
#PMID    NCBI_Gene       Mentions        Resource
psql "$db" -c "\copy gene2pubtator_raw(pmid,gene_id,mention,resource) \
              FROM STDIN DELIMITER E'\t' CSV HEADER QUOTE E'\r';" \
              <"$pubmed_data_dir/gene2pubtator_long.tsv"

psql "$db" -c "CREATE TABLE organism2pubtator_raw AS \
              TABLE organism2pubtator \
              WITH NO DATA;"
# These files don't quote any fields, so we give PostgreSQL a dummy value
# of '\r' for the quote character, which doesn't exist in these files.
if grep -q $'\r' "$pubmed_data_dir/organism2pubtator_long.tsv"; then
  echo "file includes carriage return(s), so cannot use as quote character." >/dev/stderr
  exit 1
fi
#PMID    TaxID   Mentions        Resource
psql "$db" -c "\copy organism2pubtator_raw(pmid,organism_id,mention,resource) \
              FROM STDIN DELIMITER E'\t' CSV HEADER QUOTE E'\r';" \
              <"$pubmed_data_dir/organism2pubtator_long.tsv"

# Tables 'pmids' and 'genes' are currently pretty much just placeholders.

echo "Loading pmids..."
psql "$db" -c "INSERT INTO pmids(pmid) \
              SELECT pmid FROM pmcs_raw WHERE pmid IS NOT NULL \
              UNION SELECT pmid FROM gene2pubmed_raw \
              UNION SELECT pmid FROM gene2pubtator_raw \
              UNION SELECT pmid FROM organism2pubtator_raw;"

echo "Loading genes..."
psql "$db" -c "INSERT INTO genes(gene_id) \
              SELECT gene_id FROM gene2pubmed_raw \
              UNION SELECT gene_id FROM gene2pubtator_raw;"

psql "$db" -c "CREATE TABLE merged_organisms_mapper( \
                PRIMARY KEY (from_organism_id, to_organism_id), \
                from_organism_id integer, \
                to_organism_id integer \
              );"

# We need this table in order to ensure gene2pubmed and organism2pubtator use
# the latest organism_ids, not old organism_ids that have been merged.
psql "$db" -c "INSERT INTO merged_organisms_mapper(from_organism_id, to_organism_id) \
              SELECT DISTINCT COALESCE(old_organism_id, organism_id) AS from_organism_id, \
                organism_id AS to_organism_id \
              FROM organism_names_raw \
              LEFT JOIN merged_organisms ON organism_names_raw.organism_id = merged_organisms.new_organism_id;"

# start loading into proper tables

psql "$db" -c "INSERT INTO organisms(organism_id,scientific_name) \
              SELECT organism_id,COALESCE(unique_name,name) AS scientific_name \
              FROM organism_names_raw \
              WHERE name_class='scientific name';"

psql "$db" -c "INSERT INTO organism_names(organism_id,name,unique_name,name_class) \
              SELECT DISTINCT * \
              FROM organism_names_raw;"

psql "$db" -c "INSERT INTO gene2pubmed(pmid,organism_id,gene_id) \
              SELECT DISTINCT pmid,to_organism_id,gene_id \
              FROM gene2pubmed_raw \
              INNER JOIN merged_organisms_mapper \
              ON gene2pubmed_raw.organism_id = merged_organisms_mapper.from_organism_id;"

psql "$db" -c "INSERT INTO gene2pubtator(pmid,gene_id,mention,resource) \
              SELECT DISTINCT pmid,gene_id,mention,resource \
              FROM gene2pubtator_raw";

psql "$db" -c "INSERT INTO organism2pubtator(pmid,organism_id,mention,resource) \
              SELECT DISTINCT pmid,to_organism_id,mention,resource \
              FROM organism2pubtator_raw \
              INNER JOIN merged_organisms_mapper \
              ON organism2pubtator_raw.organism_id = merged_organisms_mapper.from_organism_id;" 

# TODO: should we specify TEMPORARY for these tables instead?
psql "$db" -c "DROP TABLE pmcs_raw;"
psql "$db" -c "DROP TABLE organism_names_raw;"
psql "$db" -c "DROP TABLE gene2pubmed_raw;"
psql "$db" -c "DROP TABLE gene2pubtator_raw;"
psql "$db" -c "DROP TABLE organism2pubtator_raw;"
psql "$db" -c "DROP TABLE merged_organisms_mapper;"
