queries = {
    "issues": {
        "all": """
              query ($owner: String!, $repo: String! $cursor: String) {
                repository(owner: $owner, name: $repo) {
                  issues(first: 100, after: $cursor) {
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
              """,
        "comments": """
        query ($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $repo) {
            issue(number: $number) {
              comments(first: 100, after: $cursor) {
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
        """,
    },
    "discussions": {
        "all": """
              query ($owner: String!, $repo: String! $cursor: String) {
                repository(owner: $owner, name: $repo) {
                  discussions(first: 100, after: $cursor) {
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
                        category {
                          id
                          name
                          description
                        }
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
              """,
        "comments": """
        query ($owner: String!, $repo: String!, $number: Int!, $cursor: String) {
          repository(owner: $owner, name: $repo) {
            discussion(number: $number) {
              comments(first: 100, after: $cursor) {
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
        """,
    },
}
