.PHONY: build check test clean lock dev

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
