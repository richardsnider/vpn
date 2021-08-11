FROM registry.hub.docker.com/library/ubuntu:21.10
RUN apt-get update
RUN apt-get install --yes iproute2 wireguard

COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh
