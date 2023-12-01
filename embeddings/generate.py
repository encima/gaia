from transformers import BertTokenizer, BertModel
import torch
import psycopg2
from config import settings
from supabase import create_client, Client

# Supabase setup
url: str = "http://127.0.0.1:54321"  # Replace with your Supabase project URL
key: str = settings['SB_LOCAL_TOKEN']
supabase: Client = create_client(url, key)

def generate_embedding(text):
    tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
    model = BertModel.from_pretrained('bert-base-uncased')
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
    outputs = model(**inputs)
    return outputs.last_hidden_state.mean(dim=1).detach().numpy()[0]

conn = psycopg2.connect(host='0.0.0.0', dbname="postgres", user="postgres", password="postgres", port=54322)
cursor = conn.cursor()

cursor.execute("SELECT id, title, body FROM issues where id not in (select issue_id from issue_embeds)")
issues = cursor.fetchall()

for issue in issues:
    embedding = generate_embedding(issue[1] + ": " + issue[2])
    e_data = {
        'issue_id': issue[0],
        'embedding': embedding.tolist()
    }
    try:
        response = supabase.table('issue_embeds').insert(e_data).execute()
        print(response)
    except Exception as e:
        print(f"Error inserting {issue[0]}: {response['content']}")
        break

conn.commit()
cursor.close()
conn.close()
