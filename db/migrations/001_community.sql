create table users (
  id bigint generated always as identity primary key,
  github_id bigint not null unique,
  login text not null,
  admin boolean not null default false,
  banned boolean not null default false,
  created_at timestamptz not null default now()
);

create table sessions (
  token_hash bytea primary key,
  user_id bigint not null references users (id),
  created_at timestamptz not null default now()
);

create table posts (
  id bigint generated always as identity primary key,
  user_id bigint not null references users (id),
  title text not null,
  body text not null,
  score integer not null default 1,
  comment_count integer not null default 0,
  deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create index posts_newest on posts (created_at desc) where not deleted;

create index posts_by_user on posts (user_id, created_at);

create table post_votes (
  post_id bigint not null references posts (id),
  user_id bigint not null references users (id),
  value smallint not null check (value in (-1, 1)),
  primary key (post_id, user_id)
);

create table comments (
  id bigint generated always as identity primary key,
  post_id bigint not null references posts (id),
  parent_id bigint references comments (id),
  depth integer not null,
  user_id bigint not null references users (id),
  body text not null,
  score integer not null default 1,
  deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create index comments_by_post on comments (post_id);

create index comments_by_user on comments (user_id, created_at);

create table comment_votes (
  comment_id bigint not null references comments (id),
  user_id bigint not null references users (id),
  value smallint not null check (value in (-1, 1)),
  primary key (comment_id, user_id)
);

create table notices (
  id bigint generated always as identity primary key,
  user_id bigint not null references users (id),
  body text not null,
  created_at timestamptz not null default now()
);

create index notices_by_user on notices (user_id);

create table photos (
  post_id bigint not null references posts (id),
  position integer not null,
  file text not null,
  width integer not null,
  height integer not null,
  primary key (post_id, position)
);
