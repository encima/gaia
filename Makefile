setup:
    pipenv install
	supabase init
    supabase start

extract:
    pipenv run python3 1_github_extract.py

ingest:
    pipenv run python3 2_supabase_ingest.py

embed:
    pipenv run python3 3_generate.py

config:
	vim settings.json

web:
    cd web && reflex run

all: setup extract ingest embed