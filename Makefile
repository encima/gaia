setup:
    pipenv install
	supabase init

extract:
    pipenv run python3 gh_extract.py

ingest:
    pipenv run python3 sb_ingest.py

embed:
    cd embeddings && pipenv run python3 generate.py

config:
	vim settings.json

all: setup extract ingest embed