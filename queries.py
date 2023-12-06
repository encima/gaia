comments ='''
        query ($owner: String!, $repo: String!, $number: Int!, $commentsCursor: String) {
          repository(owner: $owner, name: $repo) {
            {gh_type}(number: $number) {
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
        '''.format(gh_type)

discussions_query = '''
            query ($owner: String!, $repo: String!, $discussionsCursor: String) {
              repository(owner: $owner, name: $repo) {
                discussions(first: 100, after: $discussionsCursor) {
                  edges {
                    node {
                      id
                      number
                      title
                      body
                      author {
                        login
                      }
                      isAnswered
                      answer
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
            '''

issuess_query = '''
            query ($owner: String!, $repo: String!, $issuesCursor: String) {
              repository(owner: $owner, name: $repo) {
                issues(first: 100, after: $issuesCursor) {
                  edges {
                    node {
                      id
                      number
                      title
                      body
                      author {
                        login
                      }
                      closed
                      createdAt
                      state
                      labels
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
            '''
