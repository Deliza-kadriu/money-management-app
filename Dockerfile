FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_HOME=/opt/flutter
ENV PUB_CACHE=/workspace/.pub-cache
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN apt-get update && apt-get install -y \
    bash \
    ca-certificates \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    wget \
  && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/flutter/flutter.git "${FLUTTER_HOME}" --depth 1 --branch stable

WORKDIR /workspace

RUN flutter config --no-analytics
RUN flutter doctor

CMD ["bash"]

