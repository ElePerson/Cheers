.PHONY: lint fix test

lint:
	cd gateway && cargo clippy --all-targets

fix:
	cd gateway && cargo fmt && cargo clippy --fix --allow-dirty --allow-staged

test:
	cd gateway && cargo test
