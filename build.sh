#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

export DEBIAN_DATE=2020-01-15
export TITLE="CoreDNS/lego"
export DESCRIPTION="A dubo image for CoreDNS"
export IMAGE_NAME="coredns"

# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" 2>/dev/null 1>&2 && pwd)/helpers.sh"
