create table issue_comment_embeds (
    id serial primary key,
    comment_id varchar REFERENCES issue_comments(id),
    issue_id varchar REFERENCES issues(id),
    embedding vector(768)
);

create table discussion_comment_embeds (
    id serial primary key,
    comment_id varchar REFERENCES discussion_comments(id),
    discussion_id varchar REFERENCES discussions(id),
    embedding vector(768)
);