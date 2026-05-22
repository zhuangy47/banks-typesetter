PYTHON := .venv/bin/python
# Active issue. Empty default lets build.py pick the most-recent issues/<name>/.
# Override per invocation, e.g.  make all ISSUE=vol43-iss2
ISSUE ?=
ISSUE_ARG := $(if $(ISSUE),--issue $(ISSUE),)

.PHONY: all online print strict clean setup ui online-debug print-debug new-issue

all: setup
	$(PYTHON) build.py --mode both $(ISSUE_ARG)

online: setup
	$(PYTHON) build.py --mode online $(ISSUE_ARG)

print: setup
	$(PYTHON) build.py --mode print $(ISSUE_ARG)

strict: setup
	$(PYTHON) build.py --mode print --strict $(ISSUE_ARG)

online-debug: setup
	$(PYTHON) build.py --mode online --debug $(ISSUE_ARG)

print-debug: setup
	$(PYTHON) build.py --mode print --debug $(ISSUE_ARG)

setup: .venv/.installed

.venv/.installed: requirements.txt
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements.txt
	touch .venv/.installed

ui: setup
	BANKS_ISSUE=$(ISSUE) $(PYTHON) ui/app.py

new-issue:
	@test -n "$(ISSUE)" || { echo "Usage: make new-issue ISSUE=<name>"; exit 1; }
	@test ! -e issues/$(ISSUE) || { echo "issues/$(ISSUE) already exists"; exit 1; }
	cp -R issues/_template issues/$(ISSUE)
	@echo "Created issues/$(ISSUE) -- edit config.yaml, lftc.md, layouts, add articles/."

clean:
	rm -rf build/
