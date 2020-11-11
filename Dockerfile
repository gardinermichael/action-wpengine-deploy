FROM debian:10.6-slim

RUN apt-get update \
  && apt-get install -y git \
  && apt-get install -y wget \
  && apt-get install -y curl \
  && apt-get install -y rsync \
  && rm -rf /var/lib/apt/lists/*

RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -

RUN apt-get install -y nodejs
RUN npm install -g yarn

COPY *.sh /
RUN chmod +x /*.sh

ENTRYPOINT ["/entrypoint.sh"]
