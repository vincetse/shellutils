#!/bin/bash -eu
#
# Runs a job and retries with exponential back-off.
#
# Getopts help from Dusty Mabe
# (http://dustymabe.com/2013/05/17/easy-getopt-for-a-bash-script/)
#
# Copyright (c) 2017 Vince Tse
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

BASENAME=$(basename $0)

function help()
{
cat <<END
${BASENAME} [--help] [--backoff=10] --tries=n -- <command>

  -n|--tries    number of times to try before giving up
  -b|--backoff  sleep time to start exponential backoff [default: 60]

  -h|--help     prints this page
END
  exit 1
}

function say()
{
  local ts=$(date +"%Y-%m-%dT%H:%M:%SZ" --utc)
  echo "### ${ts} ${BASENAME}: $@"
}

OPT_TRIES=0
OPT_BACKOFF_SLEEP=60

# Call getopt to validate the provided input.
options=$(getopt -o n:b:h --long tries:,backoff:,help -- "$@")
[ $? -eq 0 ] || {
  help
}
eval set -- "$options"
while true; do
  case "$1" in
  -n|--tries)
    OPT_TRIES=$2
    shift 2
    ;;
  -b|--backoff)
    OPT_BACKOFF_SLEEP=$2
    shift 2
    ;;
  --)
    shift
    break
    ;;
  -h|--help)
    help
    shift
    ;;
  esac
done

# run the command and retry if necessary
RETV=0
for ((i=0; i<${OPT_TRIES}; i++)); do
  set +e
  say "trying command: $@"
  $@
  RETV=$?
  set -e
  [[ "${RETV}" == 0 ]] && break

  # command failed, now wait and try again
  say "failed.  waiting ${OPT_BACKOFF_SLEEP} before retry."
  sleep ${OPT_BACKOFF_SLEEP}
  OPT_BACKOFF_SLEEP=$((OPT_BACKOFF_SLEEP * 2))  
done

if [[ "${RETV}" != "0" ]]; then
  say "command failed after ${OPT_TRIES} attempt(s), giving up."
  RETV=2
fi

exit ${RETV}
