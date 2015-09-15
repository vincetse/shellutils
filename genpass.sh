#!/bin/bash

# Requires uuencode to be in the search path
# Usage: genpass.sh <length>
# Generates a random password of required length (default: 8)

$(which uuencode > /dev/null) || exit 1

DEFLEN=8
length=${1:-${DEFLEN}}
((length < 1)) && length=${DEFLEN}
curlen=0

while ((curlen < length))
do
  outstr=${outstr}$(dd if=/dev/urandom count=1 2>/dev/null | uuencode -m - | tail --lines=+2 | \
    head --lines=-1 | tr '\n' - | head --bytes=-2)
  curlen=${#outstr}
done

echo ${outstr} | cut -c-${length}
