
# DON'T FORGET to update the version number in guiguts.pl too
VERSION=1.6.0

# zip utility to use
ZIP=zip -rv9

# files to include from the root
INCLUDES=CHANGELOG.md INSTALL.md UPGRADE.md LICENSE.txt README.md THANKS.md

TARGETS= generic win mac

all: 
	@for os in $(TARGETS); do \
		echo "# Making $$os"; \
		$(MAKE) $$os; \
	done

$(TARGETS): common
	# Build tools
	mkdir guiguts/tools
	./tools/package-tools.sh $@ $$(pwd)/guiguts/tools
	./tools/adjust-package-contents.sh $@ $$(pwd)/guiguts
	# Create final zip
	$(ZIP) guiguts-$@-$(VERSION).zip guiguts

common: clean
	mkdir guiguts
	# Start with src/
	cp -a src/* guiguts
	# Remove untracked files & directories that might be in src/
	rm -rf guiguts/tools/ guiguts/header.txt guiguts/setting.rc guiguts/data/labels_en.rc
	# Copy common tools
	cp -a $(INCLUDES) guiguts

clean:
	rm -rf guiguts

distclean: clean
	rm -rf guiguts-*.zip
