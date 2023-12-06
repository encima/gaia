from transformers import BertTokenizer, BertModel
import torch
import psycopg2
from config import settings
from supabase import create_client, Client
import sys
from pprint import pprint

url: str = settings['supabase']['host']
key: str = settings['supabase']['token']
supabase: Client = create_client(url, key)

def generate_embedding(text):
    tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
    model = BertModel.from_pretrained('bert-base-uncased')
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
    outputs = model(**inputs)
    return outputs.last_hidden_state.mean(dim=1).detach().numpy()[0]

query = sys.argv[1]
to_search = sys.argv[2] if len(sys.argv) >= 3 else 'match_issues'
return_count = sys.argv[3] if len(sys.argv) >= 4 else 10
query_embeds = generate_embedding(query)

url: str = settings['supabase']['host'] 
key: str = settings['supabase']['token']
supabase: Client = create_client(url, key)

resp = supabase.rpc('match_issues', {'query_embedding': query_embeds.tolist(), 'match_threshold': 0.6, 'match_count': return_count}).execute()

for res in resp.data:
    pprint(res, indent=4)         
    print('----------------------')
