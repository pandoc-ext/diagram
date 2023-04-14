FILTER_FILE := $(wildcard *.lua)
PANDOC ?= pandoc
DIFF ?= diff

.PHONY: test
test: test-plantuml test-tikz test-dot test-asymptote

test-%: test/test-%.yaml test/input-%.md $(FILTER_FILE)
	@$(PANDOC) --defaults test/test-$*.yaml | \
	  $(DIFF) test/expected-$*.html -

sample.html: sample.md diagram.lua
	@$(PANDOC) --self-contained \
	    --lua-filter=diagram.lua \
	    --metadata=pythonPath:"python3" \
	    --metadata=title:"README" \
	    --output=$@ $<

clean:
	@rm -f sample.html
	@rm -rf tmp-latex
