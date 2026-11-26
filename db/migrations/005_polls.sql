create table polls (
  id bigint generated always as identity primary key,
  user_id bigint not null references users (id),
  question text not null,
  closed boolean not null default false,
  created_at timestamptz not null default now()
);

create table poll_options (
  id bigint generated always as identity primary key,
  poll_id bigint not null references polls (id) on delete cascade,
  position integer not null,
  label text not null
);

create index poll_options_by_poll on poll_options (poll_id, position);

create table poll_votes (
  poll_id bigint not null references polls (id) on delete cascade,
  user_id bigint not null references users (id),
  option_id bigint not null references poll_options (id) on delete cascade,
  primary key (poll_id, user_id)
);

create index poll_votes_by_option on poll_votes (option_id);

insert into polls (user_id, question)
select id, 'Who will be first to run the game from start to finish?'
from users where github_id = 0;

insert into poll_options (poll_id, position, label)
select p.id, o.position, o.label
from polls p
cross join (values
  (1, 'VIctory'),
  (2, 'VIctory fork'),
  (3, 'XCL'),
  (4, 'Five Star Recomp'),
  (5, 'Xbox2Windows'),
  (6, 'TuxBox'),
  (7, 'Palmetto'),
  (8, 'A private build'),
  (9, 'A project not listed here'),
  (10, 'An official PC version comes first')
) as o (position, label)
