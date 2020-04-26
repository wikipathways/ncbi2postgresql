#!/usr/bin/env bash

# see https://stackoverflow.com/a/246128/5354298
get_script_dir() { echo "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"; }
SCRIPT_DIR=$(get_script_dir)

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
psql "$db" -c "\i '$SCRIPT_DIR/database/create_tables.sql'"
 
echo "Loading pmids..."
psql "$db" -c "\copy pmids(pmid) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/pmids.tsv"

echo "Loading pmcs..."
psql "$db" -c "\copy pmcs(journal,issn,eissn,year,volume,issue,page,doi,pmcid,pmid,manuscript_id,release_date) \
  FROM STDIN DELIMITER ',' CSV HEADER;" \
  <"$pubmed_data_dir/PMC-ids.csv"

echo "Loading genes..."
psql "$db" -c "\copy genes(gene_id) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/genes.tsv"

echo "Loading organisms..."
# By default, the info from taxdump.tar.gz is a collection of data from different sources.
# The following code creates a table 'organisms' with just organism_id and scientific_name,
# plus organism_names with the full info from taxdump.tar.gz.
psql "$db" -c "CREATE TABLE temp_organism_names( \
	organism_id integer, \
	name text, \
	name_unique text, \
	name_class text \
);"

psql "$db" -c "\copy temp_organism_names(organism_id,name,name_unique,name_class) \
              FROM STDIN DELIMITER E'\t' CSV;" \
              <"$pubmed_data_dir/organism_names_uniq.tsv"

psql "$db" -c "INSERT INTO organisms(organism_id,scientific_name) \
              SELECT organism_id,COALESCE(name_unique,name) AS scientific_name \
              FROM temp_organism_names \
              WHERE name_class='scientific name';"

psql "$db" -c "INSERT INTO organism_names(organism_id,name,name_unique,name_class) \
              SELECT * \
              FROM temp_organism_names;"

# TODO: use an actual TEMPORARY table
psql "$db" -c "DROP TABLE temp_organism_names;"

echo "Loading gene2pubmed & organism2pubmed..."
psql "$db" -c "\copy gene2pubmed(organism_id,gene_id,pmid) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/gene2pubmed.tsv"

psql "$db" -c "\copy organism2pubmed(organism_id,pmid) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/organism2pubmed.tsv"

echo "Loading pubtator data..."
psql "$db" -c "\copy gene2pubtator(pmid,gene_id,mention,resource) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/gene2pubtator_long_uniq.tsv"

psql "$db" -c "\copy organism2pubtator(pmid,organism_id,mention,resource) \
  FROM STDIN DELIMITER E'\t' CSV HEADER;" \
  <"$pubmed_data_dir/organism2pubtator_long_uniq.tsv"
