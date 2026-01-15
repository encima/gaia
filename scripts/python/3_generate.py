import os

import psycopg2
from transformers import BertModel, BertTokenizer

from supabase import Client, create_client

from .web.config import settings

# Supabase setup
url: str = settings["supabase"]["host"]  # Replace with your Supabase project URL
key: str = settings["supabase"]["token"]
supabase: Client = create_client(url, key)

cwd = os.getcwd()


def generate_embedding(text):
    tokenizer = BertTokenizer.from_pretrained(
        cwd + "/web/gaia/transformers/bert-base-uncased-tokenizer"
    )
    model = BertModel.from_pretrained(
        cwd + "/web/gaia/transformers/bert-base-uncased-model"
    )
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
    outputs = model(**inputs)
    return outputs.last_hidden_state.mean(dim=1).detach().numpy()[0]


conn = psycopg2.connect(
    host=settings["db"]["host"],
    dbname=settings["db"]["name"],
    user=settings["db"]["user"],
    password=settings["db"]["pwd"],
    port=settings["db"]["port"],
)
cursor = conn.cursor()

cursor.execute(
    "SELECT i.title, c.issue_id, c.id, c.body FROM issue_comments c join issues i on i.id = c.issue_id where c.id not in (select comment_id from issue_comment_embeds)"
)
issues = cursor.fetchall()
print(len(issues))
for issue in issues:
    embedding = generate_embedding(issue[0] + ": " + issue[3])
    e_data = {
        "issue_id": issue[1],
        "comment_id": issue[2],
        "embedding": embedding.tolist(),
    }
    try:
        response = supabase.table("issue_comment_embeds").insert(e_data).execute()
        print(response)
    except Exception as e:
        print(f"Error inserting {issue[0]}: {response['content']}")
        break

conn.commit()
cursor.close()
conn.close()
