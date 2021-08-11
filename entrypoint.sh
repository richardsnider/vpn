#!/bin/bash
set -x
# https://www.wireguard.com/quickstart/

wg genkey > privatekey
wg pubkey < privatekey > publickey

ip link add dev wg0 type wireguard
ip address add dev wg0 $SERVER_IP_1 peer $SERVER_IP_2
wg setconf wg0 myconfig.conf
wg set wg0 listen-port 51820 private-key $PRIVATE_KEY_PATH peer $PEER_URL allowed-ips 10.0.0.0/8 endpoint $SERVER_URL:80

ip link set up dev wg0
