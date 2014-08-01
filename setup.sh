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

setupmode=0

until [ "x$setupmode" == "x1" ] || [ "x$setupmode" == "x2" ];
do
  read -p "How would you like to run the Public Key agent? Options => 1:Sysv/Init.d, 2:Upstart (Enter 1/2):" -n 1 setupmode
  echo
done

case $setupmode in
  1)
  echo "Setting up PubKey agent as an init.d service"
  cp ./setup/pkagent.sh /etc/init.d/pkagent && chmod 555 /etc/init.d/pkagent && update-rc.d pkagent defaults 1>/dev/null && update-rc.d pkagent enable 1>/dev/null
  rm -f /etc/init/pkagent.conf
  ;;
  2)
  echo "Setting up PubKey agent as an Upstart managed service"
  if [ -f /etc/init.d/pkagent ]; then
   update-rc.d pkagent disable 2>&1 1>/dev/null
   update-rc.d pkagent remove 2>&1 1>/dev/null
   rm -f /etc/init.d/pkagent
  fi
  cp ./setup/pkagent.upstart.conf /etc/init/pkagent.conf && chmod 444 /etc/init/pkagent.conf
  ;;
  *)
  echo "Invalid option"
  exit 1
esac

echo "Setup up pubkeyagent.yml config (See http://docs.pubkey.in/agentsetup) and start the agent as 'service pkagent start'"

