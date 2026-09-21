ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG SNAPSHOT
COPY config/bootstrap-ca.pem /etc/ssl/certs/ca-certificates.crt
# The snapshot is signed by the archive key already in the official image.
RUN printf 'Types: deb\nURIs: http://snapshot.ubuntu.com/ubuntu/%s/\nSuites: noble noble-updates noble-security\nComponents: main universe\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\nCheck-Valid-Until: no\n' "$SNAPSHOT" > /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get -o APT::Update::Error-Mode=any update && apt-get install -y --no-install-recommends \
    autoconf automake build-essential ca-certificates cmake curl git gnupg \
    libtool meson nasm ninja-build pkg-config python3 ruby ruby-thor \
    texinfo xz-utils yasm qemu-user openssl fonts-dejavu-core fontconfig gperf gettext \
    && dpkg-query -W > /usr/local/share/builder-packages.txt
WORKDIR /work
