from langchain.document_loaders import JSONLoader

import json
from pathlib import Path
from pprint import pprint

def metadata_func(record: dict, metadata: dict) -> dict:

    metadata["sender_name"] = record.get("sender_name")
    metadata["timestamp_ms"] = record.get("timestamp_ms")

    return metadata

loader = JSONLoader(
    file_path='./repos/supabase_issues.json',
    jq_schema='.issues[].body',
    text_content=False)