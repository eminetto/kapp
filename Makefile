CURRENT_DIR?=$(shell pwd)
BUILDDIR:=$(CURRENT_DIR)/release

NAME:=kapp
PKG:=github.com/peterj/$(NAME)
GOOSARCHES=darwin/amd64
VERSION_FILE:=VERSION.txt

VERSION=$(shell cat ./$(VERSION_FILE))
GITCOMMIT:=$(shell git rev-parse --short HEAD)
GITUNTRACKEDCHANGES:=$(shell git status --porcelain --untracked-files=no)
ifneq ($(GITUNTRACKEDCHANGES),)
	GITCOMMIT := $(GITCOMMIT)-dirty
endif

# Sets the actual GITCOMMIT and VERSION values 
VERSION_INFO=-X $(PKG)/version.GITCOMMIT=$(GITCOMMIT) -X $(PKG)/version.VERSION=$(VERSION)

# Set the linker flags
GO_LDFLAGS=-ldflags "-w $(VERSION_INFO)"

all: build fmt lint test vet

# Builds the binary
.PHONY: build
build:
	@echo "-> $@"
	CGO_ENABLED=0 go build -i -installsuffix cgo ${GO_LDFLAGS} -o $(NAME) .

# Installs the binary
.PHONY: install
install:
	@echo "+ $@"
	go install -a -tags "$(BUILDTAGS)" ${GO_LDFLAGS} .

# Gofmts all code (sans vendor folder) just in case not using automatic formatting
.PHONY: fmt
fmt: 
	@echo "-> $@"
	@gofmt -s -l . | grep -v vendor | tee /dev/stderr

# Runs golint
.PHONY: lint
lint:
	@echo "-> $@"
	@golint ./... | grep -v vendor | tee /dev/stderr

# Runs all tests
.PHONY: test
test:
	@echo "-> $@"
	@go test -v $(shell go list ./... | grep -v vendor)

# Runs tests with coverage
.PHONY: cover
cover:
	@echo "" > coverage.txt
	@for d in $(shell go list ./... | grep -v vendor); do \
		go test -race -coverprofile=profile.out -covermode=atomic "$$d"; \
		if [ -f profile.out ]; then \
			cat profile.out >> coverage.txt; \
			rm profile.out; \
		fi; \
	done;

# Runs govet
.PHONY: vet
vet:
	@echo "-> $@"
	@go vet $(shell go list ./... | grep -v vendor) | tee /dev/stderr

# Bumps the version of the service
.PHONY: bump-version
bump-version:
	$(eval NEW_VERSION = $(shell echo $(VERSION) | awk -F. '{$NF+=1; OFS=FS} {$1 = $1; printf "%s",$0}'))
	@echo "Bumping VERSION.txt from $(VERSION) to $(NEW_VERSION)"
	echo $(NEW_VERSION) > VERSION.txt
	git add VERSION.txt README.md
	git commit -vsam "Bump version to $(NEW_VERSION)"

# Create a new git tag to prepare to build a release
.PHONY: tag
tag:
	git tag -sa $(VERSION) -m "$(VERSION)"
	@echo "Run git push origin $(VERSION) to push your new tag to GitHub and trigger build."

define buildrelease
GOOS=$(1) GOARCH=$(2) CGO_ENABLED=1 go build \
	 -o $(BUILDDIR)/$(NAME)-$(1)-$(2) \
	 -a -tags "$(BUILDTAGS) static_build netgo" \
	 -installsuffix netgo ${GO_LDFLAGS_STATIC} .;
md5sum $(BUILDDIR)/$(NAME)-$(1)-$(2) > $(BUILDDIR)/$(NAME)-$(1)-$(2).md5;
shasum -a 256 $(BUILDDIR)/$(NAME)-$(1)-$(2) > $(BUILDDIR)/$(NAME)-$(1)-$(2).sha256;
endef

# Builds the cross-compiled binaries, naming them in such a way for release (eg. binary-GOOS-GOARCH)
.PHONY: release
release: *.go VERSION.txt
	@echo "+ $@"
	$(foreach GOOSARCH,$(GOOSARCHES), $(call buildrelease,$(subst /,,$(dir $(GOOSARCH))),$(notdir $(GOOSARCH))))
