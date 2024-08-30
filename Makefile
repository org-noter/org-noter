export EMACS ?= $(shell which emacs)
CASK_DIR := $(shell cask package-directory)

$(CASK_DIR): Cask
	cask install
	@touch $(CASK_DIR)

.PHONY: cask
cask: $(CASK_DIR)

.PHONY: compile
compile: cask
	! (cask eval "(let ((byte-compile-error-on-warn f)) \
	                 (cask-cli/build))" 2>&1 \
	   | egrep -a "(Warning|Error):") ; \
	  (ret=$$? ; cask clean-elc && exit $$ret)

.PHONY: test
test: compile
	cask exec buttercup -L .


# The file where the version needs to be replaced
TARGET_FILE = org-noter.el

# Target to display the current version without overwriting the VERSION file
current-version:
	@CURRENT_VERSION=$$(svu current); \
	echo "Current Version: $$CURRENT_VERSION"

# Target to bump the patch version
bump-patch:
	@NEW_VERSION=$$(svu patch); \
	sed -i.bak -E "s/^;; Version:.*/;; Version: $$NEW_VERSION/" $(TARGET_FILE); \
	echo "New Patch Version: $$NEW_VERSION"; \
	git add $(TARGET_FILE); \
	git commit -m "Bump patch version to $$NEW_VERSION"; \
	git tag "$$NEW_VERSION"; \
	echo "Don't forget to push the new tag."


# Target to bump the minor version
bump-minor:
	@NEW_VERSION=$$(svu minor); \
	sed -i.bak -E "s/^;; Version:.*/;; Version: $$NEW_VERSION/" $(TARGET_FILE); \
	echo "New Patch Version: $$NEW_VERSION"; \
	git add $(TARGET_FILE); \
	git commit -m "Bump minor version to $$NEW_VERSION"; \
	git tag "$$NEW_VERSION"; \
	echo "Don't forget to push the new tag."

.PHONY: current-version bump-patch bump-minor
