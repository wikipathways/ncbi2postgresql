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

####################################
# organism names from taxdump.tar.gz
# ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump_readme.txt
####################################

taxonomy_data_dir="$pubmed_data_dir/taxonomy"
mkdir -p "$taxonomy_data_dir"
cd "$taxonomy_data_dir"

wget ftp://ftp.ncbi.nih.gov/pub/taxonomy/taxdump.tar.gz
#gunzip -c taxdump.tar.gz | tar xf -
tar -xzf taxdump.tar.gz merged.dmp names.dmp

# merged.dmp
# ----------
# Merged nodes file fields:
# 
# 	old_tax_id                              -- id of nodes which has been merged
# 	new_tax_id                              -- id of nodes which is result of merging

# names.dmp
# ---------
# Taxonomy names file has these fields:
# 
# 	tax_id					-- the id of node associated with this name
# 	name_txt				-- name itself
# 	unique name				-- the unique variant of this name if name not unique
# 	name class				-- (synonym, common name, ...)

# add column headers
echo -e 'old_tax_id\tnew_tax_id' >merged.dmp.tsv
echo -e 'tax_id\tname_txt\tunique_name\tname_class' >names.dmp.tsv

# convert to tsv
for f in *.dmp; do
  pre_delimiter_count=$(grep -c $'\t\|\t' "$f")

  # remove extraneous final "delimiter"
  sed -E 's#\t\|$##g' "$f" |\
    # change delimiter from '\t\|\t' to just '\t'
    sed -E 's#\t\|\t#\t#g' >>"$f".tmp

  if grep -q $'\r' "$f"; then
    echo "$f includes carriage return(s), so cannot use as quote character." >/dev/stderr
    exit 1
  fi

  post_delimiter_count=$(grep -c $'\t' "$f".tmp)
  if [[ $pre_delimiter_count -ne $post_delimiter_count ]]; then
    echo "It appears there are tab characters used as something other than delimiters." >/dev/stderr
    echo "pre: $pre_delimiter_count vs post: $post_delimiter_count" >/dev/stderr
    exit 1
  fi

  cat "$f".tmp >>"$f".tsv
done

# return to pubmed data directory
cd "$pubmed_data_dir"

#####################
# gene2pubmed
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/gene/DATA/gene2pubmed.gz
gunzip gene2pubmed.gz
mv gene2pubmed gene2pubmed.tsv

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

# PostgreSQL can handle importing \n or \r\n, so we don't need to worry about
# converting line endings from Windows format to Unix format.
#
# At one point, PMC-ids.csv had row with a field that had a '\n' in it, but the
# fields weren't quoted, so it wasn't possible to parse it correctly.
# This was what the row looked like:
#   Transbound Emerg Dis,1865-1674,1865-1682,2017,65,Suppl.
#   1,199,10.1111/tbed.12682,PMC6190748,28984428,,live^M
# To ensure that issue doesn't crop up again, here's a check:
if [ "$(grep -c $'\n' PMC-ids.csv)" -ne "$(grep -c $'\r' PMC-ids.csv)" ]; then
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

#####################
# gene2pubtator
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/pub/lu/PubTator/gene2pubtator.gz
gunzip gene2pubtator.gz

# Reshape wide -> long
# There can be multiple genes per row, split by ',' or ';'.
awk -F '\t' -v OFS='\t' '{split($2,a,/,|;/); for(i in a) print $1,a[i],$3,$4}' gene2pubtator |\
  # There can be multiple Mentions per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($3,a,/\|/); for(i in a) print $1,$2,a[i],$4}' |\
  # There can be multiple Resources per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($4,a,/\|/); for(i in a) print $1,$2,$3,a[i]}' \
  >gene2pubtator_long.tsv
rm gene2pubtator

# There are some duplicates, e.g.:
# 9892355        84557,81631     light chain-3 of microtubule-associated proteins 1A and 1B      GNormPlus
# 9892355        84557;81631     light chain-3 of microtubule-associated proteins 1A and 1B      GNormPlus
# Does that mean the phrase above appears multiple times? Or is it a mistake?
# I checked the abstract, it only appears once there. I didn't check the body text.

#####################
# organism2pubtator
#####################
wget ftp://ftp.ncbi.nlm.nih.gov/pub/lu/PubTator/species2pubtator.gz
gunzip species2pubtator.gz

# Reshape wide -> long
# There can be multiple organisms per row, split by ',' or ';'
awk -F '\t' -v OFS='\t' '{split($2,a,/,|;/); for(i in a) print $1,a[i],$3,$4}' species2pubtator |\
  # There can be multiple Mentions per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($3,a,/\|/); for(i in a) print $1,$2,a[i],$4}' |\
  # There can be multiple Resources per row, split by '|'
  awk -F '\t' -v OFS='\t' '{split($4,a,/\|/); for(i in a) print $1,$2,$3,a[i]}' \
  >organism2pubtator_long.tsv
rm species2pubtator

# Note: some pmids are specified with leading zeros, e.g.: 02 or 0017414 or 0007502, but
# others are specified w/out, e.g.: 3 or 4.
# They get removed when importing into PostgreSQL as integers.

# There are some duplicates, e.g.:
# 9221901        10090;10090;10090       BALB/c  SR4GN
# Does that mean 'BALB/c' appears multiple times? Or is it a mistake?
# I checked the abstract, it only appears twice there. I didn't check the body text.

ls -lisha
