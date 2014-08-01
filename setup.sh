#!/bin/bash
# Pubkey Install script

RUBY=`which ruby`
GEM=`which gem`

if [ "$(id -u)" != "0" ]; then
  cat << EOF
  Sorry, but the PubKey agent needs to be run as root. Our agent code is available on https://github.com/onepowerltd/pkagent .
EOF
  exit 1
fi

if [ "x$($RUBY -v 2>/dev/null)" == "x" ] || [ "x$($GEM -v 2>/dev/null)" == "x" ]; then
  echo "Does'nt appear ruby/gem are installed yet?"
  exit 1
fi

RV=`ruby -e "puts RUBY_VERSION"`
echo $RV | grep -q 1.9
if [ $? -eq 1 ]; then
  echo "Needs Ruby 1.9.x but you have $RV"
  exit 1
fi
echo "Ok so far..."
