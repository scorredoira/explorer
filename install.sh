#!/bin/zsh
set -e
cd "$(dirname "$0")"
./build.sh
pkill -x Explorer 2>/dev/null && sleep 0.5 || true
mkdir -p ~/Applications
rm -rf ~/Applications/Explorer.app
cp -R build/Explorer.app ~/Applications/
mkdir -p ~/.local/bin
ln -sf "$PWD/scripts/explorer" ~/.local/bin/explorer
open ~/Applications/Explorer.app
echo "Installed to ~/Applications/Explorer.app, and the explorer command to ~/.local/bin"
