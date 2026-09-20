ARG BASE_IMAGE
FROM ${BASE_IMAGE}
COPY config/bootstrap-ca.pem /etc/ssl/certs/ca-certificates.crt
ARG SNAPSHOT
RUN if [ -e /etc/apt/sources.list.d/ubuntu.sources ]; then \
      printf 'Types: deb\nURIs: http://snapshot.ubuntu.com/ubuntu/%s/\nSuites: noble noble-updates noble-security\nComponents: main universe\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\nCheck-Valid-Until: no\n' "$SNAPSHOT" > /etc/apt/sources.list.d/ubuntu.sources; \
    else \
      printf 'Types: deb\nURIs: http://snapshot.debian.org/archive/debian/%s/\nSuites: trixie\nComponents: main\nSigned-By: /usr/share/keyrings/debian-archive-keyring.gpg\nCheck-Valid-Until: no\n' "$SNAPSHOT" > /etc/apt/sources.list.d/debian.sources; \
    fi
RUN apt-get -o APT::Update::Error-Mode=any update && apt-get install -y --no-install-recommends \
    ruby ca-certificates libstdc++6 libgcc-s1 openssl qemu-user binutils
WORKDIR /test
