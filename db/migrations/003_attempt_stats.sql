alter table attempts
  add column stars integer not null default 0,
  add column forks integer not null default 0,
  add column issues integer not null default 0,
  add column language text not null default ''
