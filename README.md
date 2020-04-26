# pubmed2postgresql

The sections below detail the steps taken to generate files and run scripts for this project.

### Install Dependencies

[Nix](https://nixos.org/nixos/nix-pills/install-on-your-running-system.html#idm140737316672400)

### Load into Database

Before any of these steps, be sure you've entered the nix-shell:

```
nix-shell
```

Get the data:

```
bash download.sh
```

Create and load the database:

```
bash create_db.sh
```

## Generating Files and Initial Tables

Do not apply upper() or remove non-alphanumerics during lexicon constuction. These normalizations will be applied in parallel to both the lexicon and extracted words during post-processing.

#### hgnc lexicon files

1.  Download `protein-coding-gene` TXT file from http://www.genenames.org/cgi-bin/statistics
2.  Import TXT into Excel, first setting all columns to "skip" then explicitly choosing "text" for symbol, alias_symbol, prev_symbol and entrez_id columns during import wizard (to avoid date conversion of SEPT1, etc)
3.  Delete rows without entrez_id mappings
4.  In separate tabs, expand 'alias symbol' and 'prev symbol' lists into single-value rows, maintaining entrez_id mappings for each row. Used Data>Text to Columns>Other:|>Column types:Text. Delete empty rows. Collapse multiple columns by pasting entrez_id before each column, sorting and stacking.
5.  Filter each list for unique pairs (only affected alias and prev)
6.  For **prev** and **alias**, only keep symbols of 3 or more characters, using:
    - `IF(LEN(B2)<3,"",B2)`
7.  Enter these formulas into columns C and D, next to sorted **alias** in order to "tag" all instances of symbols that match more than one entrez. Delete _all_ of these instances.
    - `MATCH(B2,B3:B$###,0)` and `MATCH(B2,B$1:B1,0)`, where ### is last row in sheet.
8.  Then delete (ignore) all of these instances (i.e., rather than picking one arbitrarily via a unique function)
    - `IF(AND(ISNA(C2),ISNA(D2)),A2,"")` and `IF(AND(ISNA(C2),ISNA(D2)),B2,"")`
9.  Export as separate CSV files.

#### bioentities lexicon file

1.  Starting with this file from our fork of bioentities: https://raw.githubusercontent.com/wikipathways/bioentities/master/relations.csv. It captures complexes, generic symbols and gene families, e.g., "WNT" mapping to each of the WNT## entries.
2.  Import CSV into Excel, setting identifier columns to import as "text".
3.  Delete "isa" column. Add column names: type, symbol, type2, bioentities. Turn column filters on.
4.  Filter on 'type' and make separate tabs for rows with "BE" and "HGNC" values. Sort "be" tab by "symbol" (Column B).
5.  Add a column to "hgnc" tab based on =VLOOKUP(D2,be!B$2:D$116,3,FALSE). Copy/paste B and D into new tab and copy/paste-special B and E to append the list. Sort bioentities and remove rows with #N/A.
6.  Copy f_symbol tab (from hgnc protein-coding_gene workbook) and sort symbol column. Then add entrez_id column to bioentities via lookup on hgnc symbol using =LOOKUP(A2,n_symbol.csv!$B$2:$B$19177,n_symbol.csv!$A$2:$A$19177).
7.  Copy/paste-special columns of entrez_id and bioentities into new tab. Filter for unique pairs.
8.  Export as CSV file.

#### WikiPathways human lists

1.  Download human GMT from http://data.wikipathways.org/current/gmt/
2.  Import GMT file into Excel
3.  Select complete matrix and name 'matrix' (upper left text field)
4.  Insert column and paste this in to A1

- =OFFSET(matrix,TRUNC((ROW()-ROW($A$1))/COLUMNS(matrix)),MOD(ROW()-ROW($A$1),COLUMNS(matrix)),1,1)

5.  Copy equation down to bottom of sheet, e.g., at least to =ROWS(matrix)\*COLUMNS(matrix)
6.  Filter out '0', then filter for unique
7.  Export as CSV file.

### Running Database Queries

See database/README.md
