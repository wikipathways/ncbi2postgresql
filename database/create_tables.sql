/*CREATE DATABASE pfocr2018121717;*/
/*\c pfocr2018121717;*/
/*SET ROLE pfocr;*/

CREATE TABLE organisms(
  organism_id integer PRIMARY KEY,
	scientific_name text NOT NULL UNIQUE CHECK ( scientific_name <> '')
);

CREATE TABLE organism_names(
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	name text NOT NULL CHECK (name <> ''),
	name_unique text CHECK (name_unique <> ''),
	name_class text NOT NULL CHECK (name_class <> ''),
	unique(organism_id, name, name_unique, name_class)
);
/* The following is an example of a partial index:
 * https://www.postgresql.org/docs/current/indexes-partial.html
 * It ensures there are no duplicates, even though name_unique can have null values.
 * unique(...) specified above isn't enough, because the PostgreSQL docs say:
 * > For the purpose of a unique constraint, null values are not considered equal.
 * https://www.postgresql.org/docs/current/sql-createtable.html
 */
CREATE UNIQUE INDEX organism_names_null_unique_idx
ON organism_names (organism_id, name, name_unique, name_class)
WHERE name_unique IS NULL;

CREATE TABLE genes(
  gene_id integer PRIMARY KEY
);

CREATE TABLE pmids(
  pmid integer PRIMARY KEY
);

CREATE TABLE pmcs (
  pmcid text PRIMARY KEY,
	pmid integer UNIQUE NOT NULL REFERENCES pmids ON DELETE CASCADE,
  journal text CHECK (journal <> ''),
  /* surprised issn seems to have duplicates */
  issn text CHECK (issn <> ''),
  /* surprised eissn seems to have duplicates */
  eissn text CHECK (eissn <> ''),
  year integer NOT NULL,
  /* volume needs to of type text for cases like this: "31-39" */
  volume text CHECK (volume <> ''),
  /* issue needs to of type text for cases like this: "1-2" */
  issue text CHECK (issue <> ''),
  /* page needs to of type text for cases like this: "i" */
  page text CHECK (page <> ''),
  /* surprised doi seems to have duplicates */
  doi text CHECK (doi <> ''),
  manuscript_id text UNIQUE CHECK (manuscript_id <> ''),
  release_date text NOT NULL CHECK (release_date <> '')
);
/* TODO: are either of the following needed? I think they're not. */
/*
CREATE UNIQUE INDEX pmcs_pmid_manuscript_id_null_unique_idx
ON pmcs (pmid, manuscript_id)
WHERE pmid IS NULL OR manuscript_id IS NULL;
*/
/*
CREATE UNIQUE INDEX pmcs_null_unique_idx
ON pmcs (pmcid, pmid, journal, title, abstract, issn, eissn, year, volume, issue, page, doi, manuscript_id, release_date)
WHERE pmid IS NULL OR journal IS NULL OR title IS NULL OR abstract IS NULL OR
issn IS NULL OR eissn IS NULL OR volume IS NULL OR issue IS NULL OR 
page IS NULL OR doi IS NULL OR manuscript_id IS NULL;
*/

CREATE TABLE gene2pubmed (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	gene_id integer NOT NULL REFERENCES genes ON DELETE CASCADE,
	unique(gene_id, pmid)
);

CREATE TABLE organism2pubmed (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	unique(pmid, organism_id)
);

CREATE TABLE organism2pubtator (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	mention text NOT NULL CHECK (mention <> ''),
	resource text NOT NULL CHECK (resource <> ''),
	unique(pmid, organism_id, mention, resource)
);
/* I think the following can be removed. */
/*
CREATE UNIQUE INDEX organism2pubtator_null_unique_idx
ON organism2pubtator (organism_id, name, name_unique, name_class)
WHERE name_unique IS NULL;
*/
/* The following is an example of a partial index:
 * https://www.postgresql.org/docs/current/indexes-partial.html
 * It ensure there are no duplicates when one of the columns is null.
 */
/*CREATE UNIQUE INDEX organism2pubtator_mention_null_unique_idx
ON organism2pubtator (pmid, organism_id, mention, resource)
WHERE mention IS NULL;
CREATE UNIQUE INDEX organism2pubtator_resource_null_unique_idx
ON organism2pubtator (pmid, organism_id, mention, resource)
WHERE resource IS NULL;*/

/* PMID	NCBI_Gene	Mentions	Resource */
CREATE TABLE gene2pubtator (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	gene_id integer NOT NULL REFERENCES genes ON DELETE CASCADE,
	mention text NOT NULL CHECK (mention <> ''),
	resource text NOT NULL CHECK (resource <> ''),
	unique(pmid, gene_id, mention, resource)
);
