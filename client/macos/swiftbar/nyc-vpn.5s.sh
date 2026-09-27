#!/bin/zsh
# SwiftBar plugin: menu bar UI for nyc-vpn. State comes from files written by the root job,
# so the icon changes the instant a state file does (the job also pings SwiftBar on changes).
JOB=system/com.sauersec.nyc-vpn
STATE=/var/db/nyc-vpn.state
HEALTH=/var/db/nyc-vpn.health
STOPPING=/var/db/nyc-vpn.stopping
RUN="bash=/usr/bin/sudo param1=-n param2=/bin/launchctl"
RUNNING=$(pgrep -f '/usr/local/bin/nyc-vpn$')
[[ -f /var/db/nyc-vpn.released ]] && RUNNING=""

if [[ -n $RUNNING && -f $STATE && -f $STOPPING ]]; then
  echo "… | sfimage=lock.open"; echo "---"; echo "Disconnecting — restoring DNS…"
elif [[ -n $RUNNING && -f $STATE ]]; then
  P=$(sed -n 3p $STATE | tr a-z A-Z)
  NET=""; LAB=""; TS=0
  [[ -f $HEALTH ]] && read -r NET LAB TS < $HEALTH
  AGE=$(( $(date +%s) - TS ))
  if [[ -z $NET ]]; then
    echo "$P | sfimage=lock.shield"; echo "---"; echo "Connected via $P — checking health…"
  elif [[ $NET == ok && $LAB == ok && $AGE -lt 90 ]]; then
    echo "$P | sfimage=lock.shield.fill"; echo "---"; echo "Connected via $P"
    echo "Internet ✓   Lab DNS ✓   (checked ${AGE}s ago)"
  else
    echo "$P | sfimage=exclamationmark.shield.fill sfcolor=red color=red"; echo "---"
    echo "Connected via $P — NOT WORKING | color=red"
    echo "Internet: $NET   Lab DNS: $LAB   (checked ${AGE}s ago)"
  fi
  echo "Reconnect (re-pick path) | $RUN param3=kickstart param4=-k param5=$JOB terminal=false refresh=true"
  echo "Disconnect | $RUN param3=kill param4=TERM param5=$JOB terminal=false refresh=true"
elif [[ -n $RUNNING && ! -f $STOPPING ]]; then
  echo "… | sfimage=lock.shield"; echo "---"; echo "Connecting (testing REALITY, then CDN)…"
  echo "Cancel | $RUN param3=kill param4=TERM param5=$JOB terminal=false refresh=true"
else
  echo "| sfimage=lock.open"; echo "---"; echo "Disconnected"
  echo "Connect | $RUN param3=kickstart param4=-k param5=$JOB terminal=false refresh=true"
  echo "Open network login page | href=http://captive.apple.com"
fi
echo "---"
echo "Show log | bash=/usr/bin/open param1=-a param2=Console param3=/var/log/nyc-vpn.log terminal=false"
echo "Restore DNS now | bash=/usr/bin/sudo param1=-n param2=/usr/local/bin/nyc-vpn-restore terminal=false refresh=true"
