alter table posts
  add column pinned boolean not null default false,
  add column locked boolean not null default false;

insert into users (github_id, login) values (0, 'System');

insert into posts (user_id, title, body, pinned, locked)
select id, 'Posting rules', 'What to post

Anything about getting the game to run on a PC: results, logs, questions, write-ups. If it would interest someone working on a port, it belongs here.

Release date guesses, console news and complaints about the game do not.

Posts

Say what you tried and what happened. Name the hardware, the version of the tool and the point where it stopped.

Write the title as a plain statement. No capitals for emphasis and no exclamation marks.

A video is a claim. Attach a log or point to source if you want it treated as a result.

Do not post game files, keys, leaked builds or directions to any of them. Such posts are deleted and the account is banned.

Links

Only links to GitHub are accepted. A message with any other link is removed when you send it. You get a notice with what you wrote, so you can send it again without the link.

Comments

Be civil. Write as you would to a colleague.

Reply to the argument, not the person. If something is wrong, say what is right.

Do not comment to say you agree or that you are waiting. Upvote instead.

Do not complain about votes. It never helps.

Limits

One post a minute. One comment every thirty seconds. Up to three photos per post, each under 8 MB.

Moderation

Posts and comments that break these rules are deleted. Threads can be closed. Accounts that keep breaking them are banned.', true, true
from users where github_id = 0;

insert into post_votes (post_id, user_id, value)
select p.id, p.user_id, 1
from posts p join users u on u.id = p.user_id
where u.github_id = 0
