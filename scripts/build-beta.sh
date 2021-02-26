#!/bin/bash

# vars for build.sh
APP_NAME="Monal"
IOS_DEVELOPER_NAME="iPhone Distribution: Anurodh Pokharel (33XS7DE5NZ)"
APP_DEVELOPER_NAME="Apple Distribution: Anurodh Pokharel (33XS7DE5NZ)"
GCC_PREPROCESSOR_DEFINITIONS="IS_ALPHA=0"
BUILD_TYPE="Debug"

# go to Monal-IM root folder
cd "$(dirname "$0")/.."

# init submodules and update to latest version
git submodule update --init --recursive
git submodule update --remote

# build beta
./scripts/build.sh