#!/bin/zsh
set -e
cd "$(dirname "$0")"
./build.sh
pkill -x Explorer 2>/dev/null && sleep 0.5 || true
mkdir -p ~/Applications
rm -rf ~/Applications/Explorer.app
cp -R build/Explorer.app ~/Applications/
open ~/Applications/Explorer.app
echo "Instalada en ~/Applications/Explorer.app"
