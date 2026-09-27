#!/bin/zsh
# Installs the macOS client. Run from this directory. Requires Homebrew.
# Your config must already exist at /usr/local/etc/nyc-vpn/client.json (see client/config/README.md).
set -e
cd "${0:A:h}"

brew list sing-box >/dev/null 2>&1 || brew install sing-box
brew pin sing-box
brew list --cask swiftbar >/dev/null 2>&1 || brew install --cask swiftbar

[[ -f /usr/local/etc/nyc-vpn/client.json ]] || { echo "Missing /usr/local/etc/nyc-vpn/client.json"; exit 1 }
sudo /opt/homebrew/bin/sing-box check -c /usr/local/etc/nyc-vpn/client.json

sudo install -d -m 755 /usr/local/bin
sudo install -m 755 -o root -g wheel bin/nyc-vpn bin/nyc-vpn-restore /usr/local/bin/

for p in launchd/*.plist; do
  label=$(basename $p .plist)
  sudo install -m 644 -o root -g wheel $p /Library/LaunchDaemons/
  sudo launchctl bootout system/$label 2>/dev/null || true
  sudo launchctl bootstrap system /Library/LaunchDaemons/$label.plist
done

tmp=$(mktemp)
sed "s/<USER>/$USER/" sudoers/nyc-vpn > $tmp
sudo visudo -cf $tmp
sudo install -m 0440 -o root -g wheel $tmp /etc/sudoers.d/nyc-vpn
rm -f $tmp

sudo install -m 644 -o root -g wheel newsyslog/nyc-vpn.conf /etc/newsyslog.d/nyc-vpn.conf

mkdir -p ~/SwiftBar
install -m 755 swiftbar/nyc-vpn.5s.sh ~/SwiftBar/
open -a SwiftBar
echo "Installed. In SwiftBar choose ~/SwiftBar as the plugin folder and enable Launch at Login."
