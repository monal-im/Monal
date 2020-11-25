#!/bin/bash

echo "Resetting repository to newest origin/develop state..."
echo ""
git fetch origin
git reset --hard origin/develop
