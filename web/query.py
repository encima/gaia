from transformers import BertTokenizer, BertModel
import torch
import psycopg2
from config import settings
from supabase import create_client, Client
import sys
from pprint import pprint
from flask_cors import CORS
from flask import Flask, send_from_directory, request, render_template, jsonify
from config import settings


app = Flask(__name__)
CORS(app)

url: str = "http://127.0.0.1:54321"  # Replace with your Supabase project URL
key: str = settings['supabase']['token']
supabase: Client = create_client(url, key)

app = Flask(__name__, static_folder='static')

@app.route('/')
def index():
    return render_template('search.html')

@app.route("/api/gen-embed")
def generate_embedding():
    text = request.args.get('text')
    tokenizer = BertTokenizer.from_pretrained('bert-base-uncased')
    model = BertModel.from_pretrained('bert-base-uncased')
    inputs = tokenizer(text, return_tensors="pt", truncation=True, max_length=512)
    outputs = model(**inputs)
    query_embeds = outputs.last_hidden_state.mean(dim=1).detach().numpy()[0]
    resp = supabase.rpc('match_issues', {'query_embedding': query_embeds.tolist(), 'match_threshold': 0.6, 'match_count': 10}).execute()
    return jsonify(resp.data)

# Serve the assets (like JavaScript, CSS, images, etc.)
@app.route('/<path:path>')
def static_files(path):
    return send_from_directory(app.static_folder, path)

if __name__ == '__main__':
    app.run(debug=True)

 
