.PHONY: build test validate install status uninstall

build:
	swift build -c release

test:
	swift run CoreSelfTests

validate:
	./scripts/validate-project.sh

install:
	./scripts/install.sh

status:
	./scripts/status.sh

uninstall:
	./scripts/uninstall.sh
