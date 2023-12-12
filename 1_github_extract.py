import json

import requests

from .web.config import settings

token = settings["GH_TOKEN"]  # Your GitHub Personal Access Token
headers = {"Authorization": f"Bearer {token}"}
graphql_url = "https://api.github.com/graphql"


# Function to execute GraphQL queries
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


# Function to fetch all comments for an issue
def fetch_all_comments(owner, repo, issue_number):
    all_comments = []
    has_next_page = True
    comments_cursor = None

    while has_next_page:
        comments_query = """
        query ($owner: String!, $repo: String!, $number: Int!, $commentsCursor: String) {
          repository(owner: $owner, name: $repo) {
            discussion(number: $number) {
              comments(first: 100, after: $commentsCursor) {
                edges {
                  node {
                    id
                    body
                    author {
                      login
                    }
                    createdAt
                    url
                    reactionGroups {
                      content
                      users {
                        totalCount
                      }
                    }
                  }
                }
                pageInfo {
                  endCursor
                  hasNextPage
                }
              }
            }
          }
        }
        """
        variables = {
            "owner": owner,
            "repo": repo,
            "number": issue_number,
            "commentsCursor": comments_cursor,
        }
        result = run_query(comments_query, variables)
        comments = (
            result.get("data", {})
            .get("repository", {})
            .get("discussion", {})
            .get("comments", {})
            .get("edges", [])
        )

        for comment in comments:
            comment_data = comment.get("node", {})
            all_comments.append(comment_data)

        page_info = (
            result.get("data", {})
            .get("repository", {})
            .get("discussion", {})
            .get("comments", {})
            .get("pageInfo", {})
        )
        comments_cursor = page_info.get("endCursor")
        has_next_page = page_info.get("hasNextPage", False)

    return all_comments


# Function to fetch issues and write to JSON
def fetch_issues_and_write_to_json(repo):
    owner, repo_name = repo.split("/")
    has_next_page = True
    issues_cursor = None

    with open(f"repos/{repo_name}_discussions.json", "w", encoding="utf-8") as file:
        file.write('{"discussions":[')  # Start of the JSON array
        first_issue = True  # Flag to handle comma placement in JSON

        while has_next_page:
            issues_query = """
            query ($owner: String!, $repo: String!, $issuesCursor: String) {
              repository(owner: $owner, name: $repo) {
                discussions(first: 100, after: $issuesCursor) {
                  edges {
                    node {
                      id
                      number
                      title
                      body
                      author {
                        login
                      }
                      createdAt
                      url
                      category
                      reactionGroups {
                        content
                        users {
                          totalCount
                        }
                      }
                      comments(first: 100) {
                        totalCount
                        edges {
                          node {
                            id
                            body
                            author {
                              login
                            }
                            url
                            reactionGroups {
                              content
                              users {
                                totalCount
                              }
                            }
                          }
                        }
                        pageInfo {
                          endCursor
                          hasNextPage
                        }
                      }
                    }
                  }
                  pageInfo {
                    endCursor
                    hasNextPage
                  }
                }
              }
            }
            """
            variables = {
                "owner": owner,
                "repo": repo_name,
                "issuesCursor": issues_cursor,
            }
            result = run_query(issues_query, variables)
            issues = (
                result.get("data", {})
                .get("repository", {})
                .get("discussions", {})
                .get("edges", [])
            )

            for issue in issues:
                if not first_issue:
                    file.write(",")  # Add comma before next issue
                first_issue = False

                issue_data = issue.get("node", {})
                comments = fetch_all_comments(
                    owner, repo_name, issue_data.get("number", 0)
                )
                issue_data["comments"] = comments
                issue_json = json.dumps(issue_data, indent=4)
                file.write(issue_json)

            page_info = (
                result.get("data", {})
                .get("repository", {})
                .get("discussions", {})
                .get("pageInfo", {})
            )
            issues_cursor = page_info.get("endCursor")
            has_next_page = page_info.get("hasNextPage", False)

        file.write("]}")  # End of the JSON array


# Main function
def main():
    for repo in settings["repos"]:
        fetch_issues_and_write_to_json(repo)


if __name__ == "__main__":
    main()
