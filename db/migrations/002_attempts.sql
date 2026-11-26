create table attempts (
  id bigint generated always as identity primary key,
  slug text not null unique,
  name text not null,
  kind text not null,
  description text not null,
  owner text not null,
  status text not null default 'nothing',
  repo text not null,
  discord text not null,
  mirrors text not null,
  readme text not null default '',
  pushed_at timestamptz,
  checked_at timestamptz not null default 'epoch',
  created_at timestamptz not null default now()
);

create table progress (
  id bigint generated always as identity primary key,
  attempt_id bigint not null references attempts (id) on delete cascade,
  status text not null,
  note text not null,
  created_at timestamptz not null default now()
);

create index progress_by_attempt on progress (attempt_id, created_at desc);

create table commits (
  attempt_id bigint not null references attempts (id) on delete cascade,
  sha text not null,
  message text not null,
  author text not null,
  committed_at timestamptz not null,
  diff text,
  primary key (attempt_id, sha)
);

create index commits_by_attempt on commits (attempt_id, committed_at desc);
