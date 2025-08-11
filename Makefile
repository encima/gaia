setup: 
    cd import && pipenv install
    cd frontend && pnpm install
    supabase link --project-ref qfsrmwxxufryrczocwuj

fe:
    cd frontend && pnpm dev

functions:
    supabase functions deploy

dump:
    supabase db dump > supabase/dumps/$(date +%Y%m%d%H%M%S).sql

