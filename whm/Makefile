# Everything runs in Docker; nothing is installed on the host.
RELEASE ?= 9
IMAGE   := infrafence-whm-test:alma$(RELEASE)
SHOTS   ?= docs/screenshots

.PHONY: image test install-test packages package-test screenshots all

image:
	docker build -q --build-arg BASE=almalinux:$(RELEASE) -t $(IMAGE) -f dev/Dockerfile.test dev >/dev/null

# Unit, controller and rendering tests, as root and as an unprivileged user.
test: image
	docker run --rm -v "$(CURDIR)":/src/whm:ro $(IMAGE) prove -r t
	docker run --rm --user 1000:1000 -v "$(CURDIR)":/src/whm:ro $(IMAGE) prove -r t

install-test:
	sh test/install-test.sh 8 9 10

packages:
	sh packaging/build.sh

package-test: packages
	sh test/package-test.sh

screenshots:
	tmp=$$(mktemp -d) && sh dev/screenshots.sh "$$tmp" en && cp "$$tmp"/png/*.png $(SHOTS)/ && rm -rf "$$tmp"

all: test install-test package-test
