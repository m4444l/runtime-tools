ARG BASE_IMAGE
FROM ${BASE_IMAGE}
RUN apt-get -o APT::Update::Error-Mode=any update && apt-get install -y --no-install-recommends fontconfig fonts-dejavu-core
