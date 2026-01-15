import json

import requests

from config import settings
import graphql_queries


token = settings["GH_TOKEN"]  # Your GitHub Personal Access Token
headers = {"Authorization": f"Bearer {token}"}
graphql_url = "https://api.github.com/graphql"


def run_query(query, variables):
    request = requests.post(
        graphql_url, json={"query": query, "variables": variables}, headers=headers
    )
    if request.status_code == 200:
        return request.json()
    else:
        raise Exception(
            "Query failed to run with a return code of {}.".format(request.status_code)
        )


def fetch_all_comments(owner, repo, number, type):
    all_comments = []
    has_next_page = True
    cursor = None

    while has_next_page:
        comments_query = graphql_queries.queries[type]['comments']
        variables = {
            "owner": owner,
            "repo": repo,
            "number": number,
            "cursor": cursor
        }
        result = run_query(comments_query, variables)
        if len(result.get('errors', [])) > 0:
                  print(result)
                  raise Exception("Graphql query failed")
        
        comments = (
            result.get("data", {})
            .get("repository", {})
            .get(type == 'issues' ? 'issue' : 'discussion' , {})
            .get("comments", {})
            .get("edges", [])
        )
        
        for comment in comments:
            comment_data = comment.get("node", {})
            all_comments.append(comment_data)

        page_info = (
            result.get("data", {})
            .get("repository", {})
            .get(type == 'issues' ? 'issue' : 'discussion' , {})
            .get("comments", {})
            .get("pageInfo", {})
        )
        cursor = page_info.get("endCursor")
        has_next_page = page_info.get("hasNextPage", False)
    return all_comments


# Function to fetch issues and write to JSON
def fetch_and_write(repo, type="issues"):
    owner, repo_name = repo.split("/")
    has_next_page = True
    res_cursor = None
    print(owner, repo_name)
    try:
      with open(f"repos/{repo_name}_{type}.json", "w", encoding="utf-8") as file:
          
          type == 'issues' ? file.write('{"issues":[') : file.write('{"discussions":[')  # Start of the JSON array
          first_res = True  # Flag to handle comma placement in JSON
          while has_next_page:
              gh_query = graphql_queries.queries[type]['all']
              variables = {
                  "owner": owner,
                  "repo": repo_name,
                  "cursor": res_cursor
              }
              result = run_query(gh_query, variables)
              if len(result.get('errors', [])) > 0:
                  print(result)
                  raise Exception("Graphql query failed")
              results = (
                  result.get("data", {})
                  .get("repository", {})
                  .get(type, {})
                  .get("edges", [])
              )

              for res in results:
                  if not first_res:
                      file.write(",")  # Add comma before next issue
                  first_res = False

                  res_data = res.get("node", {})
                  comments = fetch_all_comments(
                      owner, repo_name, res_data.get("number", 0), type
                  )
                  res_data["comments"] = comments
                  res_json = json.dumps(res_data, indent=4)
                  file.write(res_json)

              page_info = (
                  result.get("data", {})
                  .get("repository", {})
                  .get(type, {})
                  .get("pageInfo", {})
              )
              res_cursor = page_info.get("endCursor")
              has_next_page = page_info.get("hasNextPage", False)

          file.write("]}")  # End of the JSON array
    except Exception as e:
        print(e)

# Main function
def main():
    for repo in settings["repos"]:
        fetch_and_write(repo, "issues")


if __name__ == "__main__":
    main()
