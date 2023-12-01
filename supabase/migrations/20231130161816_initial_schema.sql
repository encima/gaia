CREATE TABLE issues (
    id VARCHAR PRIMARY KEY,
    issue_number integer,
    repository TEXT,
    title TEXT,
    author TEXT,
    body TEXT,
    created_at TIMESTAMP,
    closed_at TIMESTAMP,
    url TEXT,
    state TEXT,
    meta JSONB
);

CREATE TABLE discussions (
    id VARCHAR PRIMARY KEY,
    repository VARCHAR(255),
    discussion_number integer,
    title TEXT,
    author TEXT,
    body TEXT,
    created_at TIMESTAMP,
    url TEXT,
    meta JSONB
);

CREATE TABLE issue_comments (
    id VARCHAR PRIMARY KEY,
    repository VARCHAR(255),
    issue_id VARCHAR REFERENCES issues(id),
    author TEXT,
    body TEXT,
    created_at TIMESTAMP,
    meta JSONB
);

CREATE TABLE discussion_comments (
    id VARCHAR PRIMARY KEY,
    repository VARCHAR(255),
    discussion_id VARCHAR REFERENCES discussions(id),
    author TEXT,
    body TEXT,
    created_at TIMESTAMP,
    meta JSONB
);
