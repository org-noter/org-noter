export EMACS ?= $(shell which emacs)
CASK_DIR := $(shell cask package-directory)

$(CASK_DIR): Cask
	cask install
	@touch $(CASK_DIR)

.PHONY: cask
cask: $(CASK_DIR)

.PHONY: compile
compile: cask
	cask emacs -batch -L . -L test \
	--eval "(setq byte-compile-error-on-warn t)" \
	-f batch-byte-compile $$(cask files); \
	(ret=$$? ; cask clean-elc && exit $$ret)
.PHONY: test coverage
test:
	rm -rf coverage
	cask exec buttercup -L .

coverage: test
	genhtml -o coverage/ coverage/lcov.info
