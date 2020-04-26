#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
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

# TODO: for nixos, mktemp uses tmpfs. so the temp dir is created in /run/user/1000/,
# But the partition that directory is mounted on doesn't have enough space.
#pubmed_data_dir="$(mktemp -d)"
pubmed_data_dir="$(pwd)/tmp"
mkdir -p "$pubmed_data_dir"
cd "$pubmed_data_dir"

echo "pubmed_data_dir: $pubmed_data_dir"

#####################
# organism names from taxdump
#####################
#
#Taxonomy names file (names.dmp):
#tax_id -- the id of node associated with this name
#name_txt -- name itself
#unique name -- the unique variant of this name if name not unique
#name class -- (synonym, common name, ...)

wget ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
tar -xzf taxdump.tar.gz names.dmp

# change delimiter from '\t\|\t' to just '\t'
# remove empty final column
# escape quotes so that PostgreSQL doesn't think the following are duplicates:
#10663     "T4-like viruses"               equivalent name
#10663     T4-like viruses         equivalent name
sed 's#"#""#g' names.dmp |\
  awk -F '\t?\\|\t?' -v OFS='"\t"' '{print $1,$2,$3,$4}' |\
  sed 's#^#"#g' |\
  sed 's#$#"#g' |\
  #
  # don't quote integer ids
  sed -E 's#^"([0-9]+)"\t#\1\t#g' |\
  #
  # Leave null values unquoted so that they are interpreted as null,
  # not empty string. See "CSV Format" section in PostgreSQL docs:
  # > NULL is written as an unquoted empty string, while an empty string data
  # > value is written with double quotes (""). 
  # https://www.postgresql.org/docs/current/sql-copy.html
  # if in first column
  sed 's#^""\t#\t#g' |\
  # middle column
  sed 's#\t""\t#\t\t#g' |\
  # last column
  sed 's#\t""$#\t#g' \
  >organism_names.tsv
rm names.dmp taxdump.tar.gz

# there are some inexplicable duplicates, e.g.:
# 876084  |       Muschampia tessellum (Hubner, 1803)     |               |       authority       |
# 876084  |       Muschampia tessellum (Hubner, 1803)     |               |       authority       |
# let's remove them.

# add column headers
head -n 1 organism_names.tsv >organism_names_uniq.tsv
# append the data, removing duplicates
tail -n +2 organism_names.tsv | sort -u >>organism_names_uniq.tsv

# organism scientific names
rg -U '"scientific\sname"$' organism_names.tsv > organism_scientific_names.tsv

#####################
# gene2pubmed
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/gene/DATA/gene2pubmed.gz
gunzip gene2pubmed.gz
mv gene2pubmed gene2pubmed.tsv

# create organism2pubmed from gene2pubmed
head -n 1 gene2pubmed.tsv | cut -f 1,3 >organism2pubmed.tsv
tail -n +2 gene2pubmed.tsv | cut -f 1,3 | sort -u >>organism2pubmed.tsv

#####################
# pmc2pmid
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/pub/pmc/PMC-ids.csv.gz
gunzip PMC-ids.csv.gz

# PMC-ids.csv uses Windows line endings: '\r\n'
# * carriage return: '\r'
# * line feed: '\n'
# For more details, see:
# https://www.cs.toronto.edu/~krueger/csc209h/tut/line-endings.html
#
# At one point, PMC-ids.csv had row with a field that had a '\n' in it, but the
# fields weren't quoted, so it wasn't possible to parse it correctly.
# This was what the row looked like:
# Transbound Emerg Dis,1865-1674,1865-1682,2017,65,Suppl.
# 1,199,10.1111/tbed.12682,PMC6190748,28984428,,live^M
#
# To ensure that issue doesn't crop up again, here's a check:
if [ "$(rg -Uc '\n' PMC-ids.csv)" -ne "$(rg -Uc '\r' PMC-ids.csv)" ]; then
  echo 'Error in PMC-ids.csv: carriage return count not equal to line feed count.' >/dev/stderr
  echo "Look at possible fix mentioned in $PROGNAME" >/dev/stderr
  # If the issue crops up again, here's a possible fix:
  #
  # mv PMC-ids.csv PMC-ids.csv.orig && tr -d '\n' | sed -E "s/\r/\r\n/g" <PMC-ids.csv.orig >PMC-ids.csv && rm PMC-ids.csv.orig
  #
  # It removes any line feeds inside fields by first removing all '\n' and then
  # replacing all '\r' with '\r\n'.
  #
  # To retain line feeds in fields, an alternative fix is to quote the fields.
  exit 1
fi

# Convert line endings from Windows format to Unix format.
dos2unix PMC-ids.csv

#####################
# gene2pubtator
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/pub/lu/PubTator/gene2pubtator.gz
gunzip gene2pubtator.gz

# Quote fields
sed 's#"#""#g' gene2pubtator |\
  # Reshape wide -> long
  # There can be multiple genes per row, split by ',' or ';'.
  awk -F '\t' -v OFS='\t' '{split($2,a,/,|;/); for(i in a) print $1,a[i],$3,$4}' |\
  # There can be multiple Mentions per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($3,a,/\|/); for(i in a) print $1,$2,a[i],$4}' |\
  # There can be multiple Resources per row, split by '|'
  awk -F '\t' -v OFS='"\t"' '{split($4,a,/\|/); for(i in a) print $1,$2,$3,a[i]}' |\
  sed 's#^#"#g' |\
  sed 's#$#"#g' |\
  #
  # don't quote integer ids
  # pmid
  sed -E 's#^"([0-9]+)"\t#\1\t#g' |\
  # gene_id
  sed -E 's#(^|\t)"([0-9]+)"(\t|$)#\1\2\3#g' |\
  #
  # Leave null values unquoted so that they are interpreted as null,
  # not empty string. See "CSV Format" section in PostgreSQL docs:
  # > NULL is written as an unquoted empty string, while an empty string data
  # > value is written with double quotes (""). 
  # https://www.postgresql.org/docs/current/sql-copy.html
  # if in first column
  sed 's#^""\t#\t#g' |\
  # middle column
  sed 's#\t""\t#\t\t#g' |\
  # last column
  sed 's#\t""$#\t#g' \
  >gene2pubtator_long.tsv
rm gene2pubtator

# there are some inexplicable duplicates, e.g.:
# 9892355        84557,81631     light chain-3 of microtubule-associated proteins 1A and 1B      GNormPlus
# 9892355        84557;81631     light chain-3 of microtubule-associated proteins 1A and 1B      GNormPlus
# let's remove them.

# add column headers
#head -n 1 gene2pubtator_long.tsv | cut -f 1,2 >gene2pubtator_long_uniq.tsv
head -n 1 gene2pubtator_long.tsv >gene2pubtator_long_uniq.tsv
# append the data
#tail -n +2 gene2pubtator_long.tsv | cut -f 1,2 | sort -u >>gene2pubtator_long_uniq.tsv
tail -n +2 gene2pubtator_long.tsv | sort -u >>gene2pubtator_long_uniq.tsv

#####################
# organism2pubtator
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/pub/lu/PubTator/species2pubtator.gz
gunzip species2pubtator.gz

# Quote fields
sed 's#"#""#g' species2pubtator |\
  # Reshape wide -> long
  # There can be multiple organisms per row, split by ',' or ';'
  awk -F '\t' -v OFS='\t' '{split($2,a,/,|;/); for(i in a) print $1,a[i],$3,$4}' |\
  # There can be multiple Mentions per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($3,a,/\|/); for(i in a) print $1,$2,a[i],$4}' |\
  # There can be multiple Resources per row, split by '|'
  awk -F '\t' -v OFS='"\t"' '{split($4,a,/\|/); for(i in a) print $1,$2,$3,a[i]}' |\
  # There are some incorrect PMIDs. The first sed is needed to fix those.
  sed -E 's/^2[0-9]*?(27[0-9]{6}\t)/\1/g' |\
  # The second sed removes leading zeros from pmids.
  sed -E 's/^0*//g' |\
  sed 's#^#"#g' |\
  sed 's#$#"#g' |\
  #
  # don't quote integer ids
  # pmid
  sed -E 's#^"([0-9]+)"\t#\1\t#g' |\
  # organism_id
  sed -E 's#(^|\t)"([0-9]+)"(\t|$)#\1\2\3#g' |\
  #
  # Leave null values unquoted so that they are interpreted as null,
  # not empty string. See "CSV Format" section in PostgreSQL docs:
  # > NULL is written as an unquoted empty string, while an empty string data
  # > value is written with double quotes (""). 
  # https://www.postgresql.org/docs/current/sql-copy.html
  # if in first column
  sed 's#^""\t#\t#g' |\
  # middle column
  sed 's#\t""\t#\t\t#g' |\
  # last column
  sed 's#\t""$#\t#g' \
  >organism2pubtator_long.tsv
rm species2pubtator

# there are some inexplicable duplicates, e.g.:
# 9221901        10090;10090;10090       BALB/c  SR4GN
# let's remove them.

# add column headers
#head -n 1 organism2pubtator_long_nonuniq.tsv | cut -f 1,2 >organism2pubtator_long_uniq.tsv
head -n 1 organism2pubtator_long.tsv >organism2pubtator_long_uniq.tsv
# append the data, removing duplicates
#tail -n +2 organism2pubtator_long.tsv | cut -f 1,2 | sort -u >>organism2pubtator_long_uniq.tsv
tail -n +2 organism2pubtator_long.tsv | sort -u >>organism2pubtator_long_uniq.tsv

echo 'creating genes.tsv...'
echo '#gene_id' >genes.tsv
# sort and take unique. exclude empties
sort -um >>genes.tsv \
  <(tail -n +2 gene2pubmed.tsv | awk -F '\t' -v OFS='\t' '{print $2}' | rg '.+' | sort -u) \
  <(tail -n +2 gene2pubtator_long_uniq.tsv | awk -F '"?\t"?' -v OFS='\t' '{print $2}' | rg '.+' | sort -u)

echo 'creating pmids.tsv...'
# pmcs doesn't contain all the pmids that exist in some of the other files, e.g.,
# gene2pubmed has pmid 9873079
echo '#pmid' >pmids.tsv
# sort and take unique. exclude empties
sort -um >>pmids.tsv \
  <(tail -n +2 PMC-ids.csv | awk -F ',' -v OFS='\t' '{print $10}' | rg '.+' | sort -u) \
  <(tail -n +2 organism2pubmed.tsv | awk -F '\t' -v OFS='\t' '{print $2}' | rg '.+' | sort -u) \
  <(tail -n +2 organism2pubtator_long_uniq.tsv | awk -F '\t' -v OFS='\t' '{print $1}' | rg '.+' | sort -u) \
  <(tail -n +2 gene2pubmed.tsv | awk -F '\t' -v OFS='\t' '{print $3}' | rg '.+' | sort -u) \
  <(tail -n +2 gene2pubtator_long_uniq.tsv | awk -F '"?\t"?' -v OFS='\t' '{print $1}' | rg '.+' | sort -u)

ls -lisha
