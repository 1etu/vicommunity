.PHONY: dev check fmt test db guard

-include .env
export

MSYS_NO_PATHCONV = 1

FORMATTED = src/vitrack.gleam $(wildcard src/vitrack/*.gleam) src/vitrack/page test

DATABASE_URL ?= postgres://postgres:postgres@localhost:5439/vitrack
check test: DATABASE_URL = postgres://postgres:postgres@localhost:5439/vitrack_test

dev:
	gleam run

check:
	gleam format --check $(FORMATTED)
	gleam build --warnings-as-errors
	gleam test

fmt:
	gleam format $(FORMATTED)

test:
	gleam test

db:
	docker start vitrack-db || docker run -d --name vitrack-db -p 127.0.0.1:5439:5432 -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=vitrack -v vitrack-db:/var/lib/postgresql postgres:18-alpine
	docker exec vitrack-db sh -c "until pg_isready -h 127.0.0.1 -U postgres -q; do sleep 1; done; createdb -h 127.0.0.1 -U postgres vitrack_test 2>/dev/null; true"

guard:
	docker start vitrack-guard || docker run -d --name vitrack-guard -p 127.0.0.1:8000:8000 -e BIND=:8000 -e TARGET=http://host.docker.internal:8001 -e POLICY_FNAME=/anubis.yaml -e USE_REMOTE_ADDRESS=true -e SERVE_ROBOTS_TXT=true -e REDIRECT_DOMAINS=localhost -v "$(CURDIR)/anubis.yaml:/anubis.yaml:ro" ghcr.io/techarohq/anubis:v1.28.2
