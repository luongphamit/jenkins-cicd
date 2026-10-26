FROM jenkins/inbound-agent:latest-jdk21
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      lsb-release curl make openssh-client \
  && curl -fsSLo /usr/share/keyrings/docker-archive-keyring.asc \
      https://download.docker.com/linux/debian/gpg \
  && echo "deb [arch=$(dpkg --print-architecture) \
      signed-by=/usr/share/keyrings/docker-archive-keyring.asc] \
      https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends \
      docker-ce-cli docker-buildx-plugin \
  && rm -rf /var/lib/apt/lists/*
USER jenkins
