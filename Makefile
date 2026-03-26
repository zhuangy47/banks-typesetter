PYTHON := .venv/bin/python

.PHONY: all online print clean setup ui

all: setup
	$(PYTHON) build.py --mode both

online: setup
	$(PYTHON) build.py --mode online

print: setup
	$(PYTHON) build.py --mode print

strict: setup
	$(PYTHON) build.py --mode print --strict

setup: .venv/.installed

.venv/.installed: requirements.txt
	python3 -m venv .venv
	.venv/bin/pip install -q -r requirements.txt
	touch .venv/.installed

ui: setup
	$(PYTHON) ui/app.py

clean:
	rm -rf build/
