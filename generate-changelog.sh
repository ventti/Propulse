#!/bin/bash
set -euo pipefail

PROJECT_DIR=$(git rev-parse --show-toplevel)
{
    echo "# Changelog"
    echo ""
    echo "## Changes introduced in the Extended version"
    echo ""
    echo "### Latest changes"
    echo ""
    git log --pretty=format:'* %as: %s (`%h`)' 0.10.0..HEAD
    echo ""
    echo ""
    echo "### v0.10.0 - Initial Extended version"
    echo ""
    git log --pretty=format:'* %as: %s (`%h`)' 8d4f62b..0.10.0
} > "${PROJECT_DIR}/release/CHANGELOG.txt"

