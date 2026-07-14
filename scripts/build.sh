#!/usr/bin/env bash
set -euo pipefail

mod_name=$(jq -r .name info.json)
mod_version=$(jq -r .version info.json)
mkdir -p dist
archive="dist/${mod_name}_${mod_version}.zip"
rm -f "$archive"
git archive --prefix "${mod_name}_${mod_version}/" HEAD -o "$archive"
