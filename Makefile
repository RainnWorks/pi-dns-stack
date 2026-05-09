HOST ?= dns1
VALID_HOSTS := dns1 dns2 kitchen-music
PROJECT_DIR := /mnt/mac$(shell pwd)
OUTPUT_DIR := $(shell pwd)/out
VM_NAME := nixbuilder
NIX := . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

IP ?=
.PHONY: init setup build flash deploy test clean help

help:
	@echo "Usage:"
	@echo "  make init             - One-time setup: config.local.nix, git hooks"
	@echo "  make setup            - Create OrbStack VM and install Nix"
	@echo "  make build HOST=dns1  - Build SD image"
	@echo "  make flash HOST=dns1  - Flash SD image to card"
	@echo "  make deploy HOST=dns1 - Push config to running node over SSH (no reflash)"
	@echo "  make test IP=x.x.x.x  - Run health checks"
	@echo "  make clean            - Remove built images"

init:
	@if [ ! -f config.local.nix ]; then \
		cp config.example.nix config.local.nix; \
		echo "Created config.local.nix from example."; \
	else \
		echo "config.local.nix already exists — leaving alone."; \
	fi
	@git add -fN config.local.nix
	@git config core.hooksPath .githooks
	@echo ""
	@echo "Setup complete:"
	@echo "  - config.local.nix is registered with git intent-to-add (visible to Nix, content not staged)"
	@echo "  - pre-commit hook installed (refuses to commit config.local.nix)"
	@echo ""
	@echo "Edit config.local.nix with your domain, IP, SSH key, and timezone."
	@echo "Then: make build HOST=dns1   (or dns2 / kitchen-music)"

setup:
	@./scripts/setup.sh

build:
	$(if $(filter $(HOST),$(VALID_HOSTS)),,$(error Unknown host '$(HOST)'. Valid: $(VALID_HOSTS)))
	@echo "Building SD image for $(HOST)..."
	@STORE_PATH=$$(orb run -m $(VM_NAME) bash -c "$(NIX) && cd $(PROJECT_DIR) && nix build .#nixosConfigurations.$(HOST).config.system.build.sdImage --no-link --print-out-paths 2>&1 | tail -1") && \
	if echo "$$STORE_PATH" | grep -q "^/nix/store/"; then \
		mkdir -p $(OUTPUT_DIR) && \
		chmod u+w $(OUTPUT_DIR)/$(HOST).img.zst 2>/dev/null; rm -f $(OUTPUT_DIR)/$(HOST).img.zst && \
		echo "Copying image to $(OUTPUT_DIR)/$(HOST).img.zst..." && \
		orb run -m $(VM_NAME) bash -c "cp $$STORE_PATH/sd-image/*.img.zst $(PROJECT_DIR)/out/$(HOST).img.zst" && \
		echo "Done:" && ls -lh $(OUTPUT_DIR)/$(HOST).img.zst; \
	else \
		echo "Error: build failed" && exit 1; \
	fi

flash:
	$(if $(filter $(HOST),$(VALID_HOSTS)),,$(error Unknown host '$(HOST)'. Valid: $(VALID_HOSTS)))
	@if [ ! -f $(OUTPUT_DIR)/$(HOST).img.zst ]; then \
		echo "Error: no image for $(HOST). Run 'make build HOST=$(HOST)' first."; \
		exit 1; \
	fi
	@./scripts/flash.sh $(HOST)

deploy:
	$(if $(filter $(HOST),$(VALID_HOSTS)),,$(error Unknown host '$(HOST)'. Valid: $(VALID_HOSTS)))
	@./scripts/deploy.sh $(HOST) $(IP)

test:
	$(if $(IP),,$(error Usage: make test IP=x.x.x.x))
	@./scripts/test.sh $(IP)

clean:
	rm -rf $(OUTPUT_DIR)
