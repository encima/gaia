from supabase import create_client, Client
import json
from config import settings

# Supabase setup
url: str = "http://127.0.0.1:54321"  # Replace with your Supabase project URL
key: str = settings['supabase']['token']
supabase: Client = create_client(url, key)

for repo in settings['repos']:
    # repo = 'repo'
    gh_type = 'issues'
    singular_type = gh_type[0:-1]
    print(singular_type)
    # Load JSON file
    json_file_path = f'repos/{repo}_{gh_type}.json'  # Replace with your JSON file path
    with open(json_file_path, 'r') as file:
        data = json.load(file)

    # Assuming 'data' is a list of issues
    for d in data[gh_type]:
        # Extract and transform issue data as per your schema
        d_data = {
            'id': d['id'],
            'repository': repo,
            'title': d['title'],
            'body': d['body'],
            'created_at': d['createdAt'],
            'author': d['author']['login'] if d['author'] else None,
            'url': d['url']
        }
        d_data['meta'] = json.dumps(d)
        try:
            response = supabase.table(gh_type).insert(d_data).execute()
        except Exception as e:
            print(f"Error inserting {gh_type} {d['id']}: {e}")
        for comments in d['comments']:
            # Extract and transform comments data as per your schema
            comment_data = {
                'id': comments['id'],
                'body': comments['body'],
                f'{singular_type}_id': d['id'],
                'author': comments['author']['login'] if comments['author'] else None,
                'created_at': comments['createdAt'],
                'repository': repo
            }
            comment_data['meta'] = json.dumps(comments)
            # Insert into the database
            try:
                response = supabase.table(f'{singular_type}_comments').insert(comment_data).execute()
            
            # Check response for success or error
            except Exception as e:
                print(f"Error inserting comment {comments['id']}: {e}")
            finally:
                print(f"Successfully inserted comment {comments['id']}")


