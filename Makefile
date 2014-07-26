.PHONY: deps
.PHONY: rel
.PHONY: all

all:rel

deps:
	./rebar get-deps

clean:
	./rebar clean

compile: deps clean
	./rebar compile

rel:compile
	./rebar generate
