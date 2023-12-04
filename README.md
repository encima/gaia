# Github Analyse Ingest and Access (GAIA)

## WHAT?

GAIA is a tool to extract issues, discussions and comments from Github, generate
embeddings for them and provide a search interface to query them.

The name is a reference to the Greek goddess of the Earth, Gaia, but it means
nothing; mostly it was chosen by selecting random verbs related to data.

## HOW?

You will need:

- This repo
- `pipenv`
- A github account (and token)
- A Supabase database (locally or in the Cloud)

Based on your `settings.py`, the tool will jump into your repos and download
issues/discussions and comments to a local JSON file. From there, you can ingest
the raw content into Postgres. You can then generate embeddings for each and
store them with `pgvector`.

Aaaand then:

1. Run `pipenv install`
2. Run `supabase init`
3. Run `pipenv run python3 gh_extract.py`
4. Data will be in `repos/`
5. Run `pipenv run python3 generate.py`
6. Run `pipenv run python3 sb_ingest.py`
