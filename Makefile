.PHONY: lint fix test docs-pages

lint:
	cd gateway && cargo clippy --all-targets

fix:
	cd gateway && cargo fmt && cargo clippy --fix --allow-dirty --allow-staged

test:
	cd gateway && cargo test

docs-pages:
	node scripts/generate-architecture-status-page.mjs
