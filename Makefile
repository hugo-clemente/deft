APP := build/App Selector.app
IDENTITY := App Selector Dev
# Sign with the stable local identity when it exists (`make cert`), else ad hoc.
SIGN ?= $(shell security find-certificate -c "$(IDENTITY)" >/dev/null 2>&1 && echo "$(IDENTITY)" || echo -)

app:
	swift build -c release
	rm -rf "$(APP)" && mkdir -p "$(APP)/Contents/MacOS"
	cp .build/release/AppSelector "$(APP)/Contents/MacOS/"
	cp Info.plist "$(APP)/Contents/"
	codesign --force --sign "$(SIGN)" "$(APP)"

# One-time: self-signed code-signing identity in the login keychain. macOS ties the Accessibility
# grant to the signing identity; an ad-hoc one changes every build, this one doesn't.
# System LibreSSL on purpose: OpenSSL 3's default .p12 encryption isn't readable by `security import`.
cert:
	@if security find-certificate -c "$(IDENTITY)" >/dev/null 2>&1; then echo "$(IDENTITY) already exists"; exit 0; fi; \
	tmp=$$(mktemp -d) && \
	printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=$(IDENTITY)\n[ext]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nbasicConstraints=critical,CA:false\n' > $$tmp/cfg && \
	/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config $$tmp/cfg -keyout $$tmp/key.pem -out $$tmp/cert.pem 2>/dev/null && \
	/usr/bin/openssl pkcs12 -export -inkey $$tmp/key.pem -in $$tmp/cert.pem -name "$(IDENTITY)" -passout pass:x -out $$tmp/id.p12 && \
	security import $$tmp/id.p12 -k login.keychain-db -P x -T /usr/bin/codesign; \
	status=$$?; rm -rf $$tmp; exit $$status

test:
	swift run AppSelector --self-test

.PHONY: app cert test
