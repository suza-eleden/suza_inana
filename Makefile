.PHONY: local-up types check test

local-up:
	supabase start

types:
	npm run types:gen

check:
	npm run typecheck
	npm run lint

test:
	npm test
