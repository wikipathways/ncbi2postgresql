# ncbi2postgresql

Import NCBI data into a PostgreSQL database. Data included:

- PMC-id
- gene2pubmed
- gene2pubtator and organism2pubtator

The sections below detail the steps taken to generate files and run scripts for this project.

## Install Dependencies

- [Nix](https://nixos.org/nixos/nix-pills/install-on-your-running-system.html#idm140737316672400)
- [direnv](https://direnv.net/)

With direnv, you will enter the Nix shell environment when you `cd` into this directory. If you don't want to use direnv, you'll have to explicitly call:

```
nix-shell
```

## Load Data into Database

Get the data:

```
bash download.sh
```

Create and load the database:

```
bash create_db.sh
```

## Related

- [PubMedPortable: A Framework for Supporting the Development of Text Mining Applications](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5051953/)
