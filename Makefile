# agent-gogcli-firewall — build the gog binaries from the local gogcli checkout.
#
#   gog                            plain binary for manual use (version-stamped,
#                                  no safety profile)
#   gog-readonly-locked            baked with safety-profiles/*-locked.yaml from this
#   gog-agent-safe-locked          the readonly / agent-safe command rules plus
#                                  pinned sanitize-content, wrap-untrusted and
#                                  no-input (and readonly on the read side), which
#                                  argv cannot override. The gog-readonly-forced
#                                  and gog-draft-forced wrappers run these under
#                                  bwrap.
#
# The unlocked readonly / agent-safe targets remain for comparison builds but are
# not part of `all`.
#
# `make` builds all three; `make update` pulls the checkout first, then rebuilds.

# Point GOGCLI at an existing checkout; otherwise it is cloned here on first build.
GOGCLI ?= $(CURDIR)/gogcli
BUILD_SAFE := $(GOGCLI)/build-safe.sh
GOGCLI_URL ?= https://github.com/openclaw/gogcli

.PHONY: all gog readonly agent-safe readonly-locked agent-safe-locked update checkout

all: checkout gog readonly-locked agent-safe-locked

# Every target below builds out of the checkout, so fetch it on first use.
checkout:
	@test -x $(BUILD_SAFE) || git clone $(GOGCLI_URL) $(GOGCLI)

gog: checkout
	cd $(GOGCLI) && make build
	cp $(GOGCLI)/bin/gog $(CURDIR)/gog

readonly-locked: checkout
	$(BUILD_SAFE) $(CURDIR)/safety-profiles/readonly-locked.yaml -o $(CURDIR)/gog-readonly-locked

agent-safe-locked: checkout
	$(BUILD_SAFE) $(CURDIR)/safety-profiles/agent-safe-locked.yaml -o $(CURDIR)/gog-agent-safe-locked

readonly: checkout
	$(BUILD_SAFE) $(GOGCLI)/safety-profiles/readonly.yaml -o $(CURDIR)/gog-readonly

agent-safe: checkout
	$(BUILD_SAFE) $(GOGCLI)/safety-profiles/agent-safe.yaml -o $(CURDIR)/gog-agent-safe

update: checkout
	cd $(GOGCLI) && git pull --ff-only
	$(MAKE) all
