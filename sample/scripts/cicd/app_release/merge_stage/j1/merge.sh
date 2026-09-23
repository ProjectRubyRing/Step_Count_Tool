#!/bin/bash
#
# マージステージ: リリースブランチを main へマージ
#
set -euo pipefail

readonly BRANCH="release/j1"

git fetch origin
git checkout main
git merge --no-ff "origin/${BRANCH}" -m "Merge ${BRANCH}"
git push origin main
