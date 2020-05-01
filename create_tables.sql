CREATE TABLE organisms(
  organism_id integer PRIMARY KEY,
	scientific_name text NOT NULL UNIQUE CHECK ( scientific_name <> '')
);

CREATE TABLE organism_names(
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	name text NOT NULL CHECK (name <> ''),
	unique_name text CHECK (unique_name <> ''),
	name_class text NOT NULL CHECK (name_class <> ''),
	unique(organism_id, name, unique_name, name_class)
);
/* The following is an example of a partial index:
 * https://www.postgresql.org/docs/current/indexes-partial.html
 * It ensures there are no duplicates, even though unique_name can have null values.
 * unique(...) specified above isn't enough, because the PostgreSQL docs say:
 * > For the purpose of a unique constraint, null values are not considered equal.
 * https://www.postgresql.org/docs/current/sql-createtable.html
 */
CREATE UNIQUE INDEX organism_names_null_unique_idx
ON organism_names (organism_id, name, unique_name, name_class)
WHERE unique_name IS NULL;

CREATE TABLE genes(
  gene_id integer PRIMARY KEY
);

CREATE TABLE pmids(
  pmid integer PRIMARY KEY
);

CREATE TABLE pmcs (
  pmcid text PRIMARY KEY,
  /* maybe pmid has duplicates when it's both a manuscript and published? */
	pmid integer REFERENCES pmids ON DELETE CASCADE,
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

CREATE TABLE gene2pubmed (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	gene_id integer NOT NULL REFERENCES genes ON DELETE CASCADE,
	unique(gene_id, pmid)
);

/* TODO: a table or a view?
CREATE TABLE organism2pubmed (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	unique(pmid, organism_id)
);
*/

CREATE VIEW organism2pubmed AS
SELECT DISTINCT pmid,organism_id
	FROM gene2pubmed;

CREATE TABLE organism2pubtator (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	organism_id integer NOT NULL REFERENCES organisms ON DELETE CASCADE,
	mention text NOT NULL CHECK (mention <> ''),
	resource text NOT NULL CHECK (resource <> ''),
	unique(pmid, organism_id, mention, resource)
);

/* PMID	NCBI_Gene	Mentions	Resource */
CREATE TABLE gene2pubtator (
	pmid integer NOT NULL REFERENCES pmids ON DELETE CASCADE,
	gene_id integer NOT NULL REFERENCES genes ON DELETE CASCADE,
	mention text NOT NULL CHECK (mention <> ''),
	resource text NOT NULL CHECK (resource <> ''),
	unique(pmid, gene_id, mention, resource)
);
