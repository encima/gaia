create extension vector;

create table issue_embeds (
    id serial primary key,
    issue_id varchar REFERENCES issues(id),
    embedding vector(768)
);

create table discussion_embeds (
    id serial primary key,
    discussion_id varchar REFERENCES discussions(id),
    embedding vector(768)
);