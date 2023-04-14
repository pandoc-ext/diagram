PANDOC ?= pandoc

.PHONY: test
test: clean sample.html

sample.html: sample.md diagram.lua
	@$(PANDOC) --self-contained \
	    --lua-filter=diagram.lua \
	    --metadata=pythonPath:"python3" \
	    --metadata=title:"README" \
	    --output=$@ $<

clean:
	@rm -f sample.html
	@rm -rf tmp-latex
