.PHONY: build check test clean lock dev install uninstall

PREFIX ?= ~/.local

build:
	dune build

check:
	dune build @check

test:
	dune test

clean:
	dune clean

lock:
	dune pkg lock

dev:
	dune exec -w bin/main.exe

install: build
	mkdir -p $(PREFIX)/bin
	rm -f $(PREFIX)/bin/axioms-sync
	cp _build/default/bin/main.exe $(PREFIX)/bin/axioms-sync

uninstall:
	rm -f $(PREFIX)/bin/axioms-sync
