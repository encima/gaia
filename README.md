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

Some resources can be found within Supabase's [docs](https://supabase.com/blog/openai-embeddings-postgres-vector)

Aaaand then:

1. Run `make setup`
2. Run `make extract` - to download the issues and comments
3. Data will be in `repos/`
4. Run `make ingest` - to insert the data into postgres
5. Run `make generate` - to generate embeddings and insert them into postgres
6. Run `pipenv run python3 query.py <SEARCH_TERM>` - to search for similar
   issues
