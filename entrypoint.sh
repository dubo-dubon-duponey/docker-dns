#!/usr/bin/env bash

[ -e /config/config.conf ] || cp config.conf /config/ || {
  >&2 printf "Failed to create default config file. Permissions issue likely.\n"
  exit 1
}

exec coredns -conf /config/config.conf "$@"
