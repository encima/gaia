import csv
import json
import requests
from dotenv import load_dotenv
import utils
from utils import queries
import os

load_dotenv()

token = os.getenv("GH_TOKEN")
headers = {"Authorization": f"Bearer {token}"}
graphql_url = "https://api.github.com/graphql"


def run_query(query, variables):
    response = requests.post(
        graphql_url, json={"query": query, "variables": variables}, headers=headers
    )
    response.raise_for_status()
    result = response.json()
    if 'errors' in result:
        raise Exception(f"GraphQL query failed: {result['errors']}")
    return result


def fetch_all_comments(owner, repo, number, type, comments_writer):
    cursor = None
    has_next_page = True

    while has_next_page:
        variables = {
            "owner": owner,
            "repo": repo,
            "number": number,
            "cursor": cursor
        }
        result = run_query(queries[type]['comments'], variables)

        comments = (
            result.get("data", {})
            .get("repository", {})
            .get('issue' if type == 'issues' else 'discussion', {})
            .get("comments", {})
            .get("edges", [])
        )

        for comment in comments:
            comment_data = comment.get("node", {})
            author = comment_data.get("author").get("login") if comment_data.get("author") else "Deleted User"
            try:
                comments_writer.writerow([
                    comment_data.get("id", ""),
                    number,
                    author,
                    comment_data.get("createdAt", ""),
                    comment_data.get("body", ""),
                    f"https://github.com/{owner}/{repo}/{type}/{number}#issuecomment-{comment_data.get('id', '')}"
                ])
            except Exception as e:
                print(comment_data)
                print(f"Error writing comment: {e}")

        page_info = (
            result.get("data", {})
            .get("repository", {})
            .get('issue' if type == 'issues' else 'discussion', {})
            .get("comments", {})
            .get("pageInfo", {})
        )
        cursor = page_info.get("endCursor")
        has_next_page = page_info.get("hasNextPage", False)


def fetch_and_write(repo, type="issues"):
    owner, repo_name = repo.split("/")
    cursor = None
    has_next_page = True

    try:
        with open(f"repos/{repo_name}_{type}.csv", "w", newline='', encoding="utf-8") as issues_file, \
             open(f"repos/{repo_name}_{type}_comments.csv", "w", newline='', encoding="utf-8") as comments_file:

            issues_writer = csv.writer(issues_file)
            comments_writer = csv.writer(comments_file)

            # Write the headers
            issues_writer.writerow(["id", "repo", "title", "body", "author", "created_at", "closed_at", "state", "url"])
            comments_writer.writerow(["id", "issue_id", "author", "created_at", "comment_body", "url"])

            while has_next_page:
                variables = {
                    "owner": owner,
                    "repo": repo_name,
                    "cursor": cursor
                }
                result = run_query(queries[type]['all'], variables)

                results = (
                    result.get("data", {})
                    .get("repository", {})
                    .get(type, {})
                    .get("edges", [])
                )

                for res in results:
                    res_data = res.get("node", {})
                    author = res_data.get("author").get("login") if res_data.get("author") else "Deleted User"
                    try:
                        issues_writer.writerow([
                            res_data.get("number", ""),
                            repo,
                            res_data.get("title", ""),
                            res_data.get("body", ""),
                            author,
                            res_data.get("createdAt", ""),
                            res_data.get("closedAt", ""),
                            res_data.get("state", ""),
                            res_data.get("url", "")
                        ])
                    except Exception as e:
                        print(res_data)
                        print(f"Error writing {type}: {e}")
                    fetch_all_comments(owner, repo_name, res_data.get("number", 0), type, comments_writer)

                page_info = (
                    result.get("data", {})
                    .get("repository", {})
                    .get(type, {})
                    .get("pageInfo", {})
                )
                cursor = page_info.get("endCursor")
                has_next_page = page_info.get("hasNextPage", False)

    except Exception as e:
        print(f"Error: {e}")


def main():
    for repo in ['supabase/supabase']:
        fetch_and_write(repo, "issues")


if __name__ == "__main__":
    main()
