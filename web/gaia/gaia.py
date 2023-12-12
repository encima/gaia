import os

import reflex as rx
from config import settings
from transformers import BertModel, BertTokenizer

from supabase import Client, create_client

url: str = settings["supabase"]["url"]
key: str = settings["supabase"]["token"]
supabase: Client = create_client(url, key)

cwd = os.getcwd()


class State(rx.State):
    """The app state."""

    prompt = ""
    results: list[tuple[str, str]] = []
    processing = False
    complete = False

    def query_matches(self):
        if self.prompt == "":
            return rx.window_alert("Prompt Empty")
        self.processing, self.complete = True, False
        try:
            tokenizer = BertTokenizer.from_pretrained(
                cwd + "/gaia//transformers/bert-base-uncased-tokenizer"
            )
            model = BertModel.from_pretrained(
                cwd + "/gaia/transformers/bert-base-uncased-model"
            )
            inputs = tokenizer(
                self.prompt, return_tensors="pt", truncation=True, max_length=512
            )
            outputs = model(**inputs)
            query_embeds = outputs.last_hidden_state.mean(dim=1).detach().numpy()[0]
            resp = supabase.rpc(
                "match_issues",
                {
                    "query_embedding": query_embeds.tolist(),
                    "match_threshold": 0.6,
                    "match_count": 10,
                },
            ).execute()
            # yield
            self.results = [(x["title"], x["url"]) for x in resp.data]
            self.processing, self.complete = False, True
        except Exception as e:
            self.processing = False
            print(e)


def get_item(item):
    return rx.list_item(
        rx.hstack(
            rx.link(item[0], href=item[1]),
        ),
    )


def index():
    return rx.center(
        rx.vstack(
            rx.heading("GAIA"),
            rx.input(placeholder="Enter a search term", on_blur=State.set_prompt),
            rx.button(
                "Search",
                on_click=State.query_matches,
                is_loading=State.processing,
                width="100%",
            ),
            rx.cond(
                State.complete,
                rx.ordered_list(
                    rx.foreach(
                        State.results,
                        get_item,
                    ),
                ),
            ),
            padding="2em",
            shadow="lg",
            border_radius="lg",
        ),
        width="100%",
        height="100vh",
    )


# Add state and page to the app.
app = rx.App()
app.add_page(index, title="GAIA")
app.compile()
