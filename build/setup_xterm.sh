#!/bin/bash
# Copyright 2026 The MathWorks, Inc.
#
# Downloads xterm.js and addons into toolbox/html/lib/xterm/.
#
# Usage (from project root):
#   bash build/setup_xterm.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
HTML_DIR="$PROJECT_DIR/toolbox/html"

cd "$HTML_DIR"

export NPM_CONFIG_REGISTRY=https://mw-npm-repository.mathworks.com/artifactory/api/npm/npm-repos/

echo "Initializing npm project..."
npm init -y

echo "Installing xterm and addons..."
npm install xterm @xterm/addon-fit @xterm/addon-serialize

echo "Copying vendor files to lib/xterm/..."
mkdir -p lib/xterm

cp node_modules/xterm/css/xterm.css   lib/xterm/xterm.css
cp node_modules/xterm/lib/xterm.js     lib/xterm/xterm.js
cp node_modules/@xterm/addon-fit/lib/addon-fit.js lib/xterm/addon-fit.js
cp node_modules/@xterm/addon-serialize/lib/addon-serialize.js lib/xterm/addon-serialize.js

echo "Cleaning up npm artifacts..."
rm -rf node_modules package.json package-lock.json

echo "Done. Vendor files are in lib/xterm/"
ls -la lib/xterm/
