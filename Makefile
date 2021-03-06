all:

EMACS = emacs
OPTS  = -Q --load "init.el"
ifndef INTERACTIVE
  OPTS := $(OPTS) --batch
endif

# * Submodules management

all: packages/stamp
packages/stamp:
	git submodule update --init
	touch $@

package-update:
	git submodule update

package-upgrade:
	git submodule update --remote


# * ELPA cache

elpa-update:
	@echo -e "\n>>>>>>>>>>"
	$(EMACS) --eval '(setq ff/updating-elpa-cache t)' $(OPTS)


# * Symbola font

all: install-fonts
install-fonts: $(HOME)/.fonts/Symbola.ttf

$(HOME)/.fonts/Symbola.ttf: share/fonts/Symbola.ttf
	mkdir -p $(HOME)/.fonts
	diff $(HOME)/.fonts/Symbola.ttf share/fonts/Symbola.ttf \
	|| (set -e; cp share/fonts/*.ttf $(HOME)/.fonts; fc-cache)


# * pydoc-info

#all: pydoc-info

PYDOC_INFO = share/info/python.info
PYDOC_INFO_BASE = $(shell dirname $${PWD}/$(PYDOC_INFO))
PYDOC_INFO_DIR = $(PYDOC_INFO_BASE)/dir

$(PYDOC_INFO):
	mkdir -p $(PYDOC_INFO_BASE)
	wget https://bitbucket.org/jonwaltman/pydoc-info/downloads/python.info.gz \
	     -O $(PYDOC_INFO).gz
	gunzip $(PYDOC_INFO).gz

$(PYDOC_INFO_DIR): $(PYDOC_INFO)
	install-info --info-dir=$(PYDOC_INFO_BASE) $(PYDOC_INFO)

pydoc-info: $(PYDOC_INFO_DIR)

distclean: pydoc-distclean
pydoc-distclean:
	$(RM) $(PYDOC_INFO_BASE)


# * Bootstrapping
bootstrap:
	@echo -e "\nBootstraping (1)..."
	@echo -e "\n>>>>>>>>>>"
	-$(EMACS) $(OPTS)
	@echo -e "\nBootstraping (2)..."
	@echo -e "\n>>>>>>>>>>"
	$(EMACS) --eval '(toggle-debug-on-error)' $(OPTS)


# * Yasnippet

all: yasnippet
yasnippet: bootstrap
	@echo -e "\n>>>>>>>>>>"
	$(EMACS) $(OPTS) --eval '(yas-recompile-all)'


# * Check

check: all
	@echo -e "\n>>>>>>>>>>"
	$(EMACS) $(OPTS) --load 'tests/check-bc.el'

check-install:
	./tests/check-install


# * Postamble

# Local Variables:
#  eval: (outline-minor-mode 1)
# End:
