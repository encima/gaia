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

And then:

1. Run `make setup`
2. Run `make extract` - to download the issues and comments
3. Data will be in `repos/`
4. Run `make ingest` - to insert the data into postgres
5. Run `make generate` - to generate embeddings and insert them into postgres
6. Run `make web` - to search for similar issues in the web interface

---


### Examples

You can explore the database and compare issues against each other with something like:

```
SELECT
    i1.id AS issue1_id,
    i1.title AS issue1_title,
    i1.url AS issue1_url,
    i1.repository AS issue1_repo,
    i2.id AS issue2_id,
    i2.title AS issue2_title,
    i2.url AS issue2_url,
    i2.repository AS issue2_repo,
    1 - (e1.embedding <=> e2.embedding) AS similarity_score
FROM
    issues i1
JOIN
    issue_embeds e1 ON i1.id = e1.issue_id
JOIN
    issues i2 ON i1.id < i2.id
JOIN
    issue_embeds e2 ON i2.id = e2.issue_id
WHERE i1.title != i2.title and LENGTH(i1.title) > 8 and LENGTH(i2.title) > 8 AND 1 - (e1.embedding <=> e2.embedding) > 0.92
ORDER BY
    similarity_score DESC
LIMIT 100;
```
