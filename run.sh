#!/bin/bash

export DOCKER_IMAGE=registry.hub.docker.com/library/wireguard:latest
export COMMAND="./some-script.sh"

docker run \
--image wireguard \
--env PRIVATE_KEY=$PRIVATE_KEY \
--volumes /lib/modules:/lib/modules \
--cap-add NET_ADMIN \
--cap-add SYS_MODULE \
--sysctl net.ipv4.conf.all.src_valid_mark=1 \
--publish 51820:51820/udp \
$DOCKER_IMAGE $COMMAND
