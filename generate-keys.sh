#!/bin/bash

wg genkey > /tmp/privatekey
wg pubkey < /tmp/privatekey > /tmp/publickey

export $WIREGUARD_SERVER_PRIVATE_KEY=$(cat privatekey)
export $WIREGUARD_SERVER_PUBLIC_KEY=$(cat publickey)