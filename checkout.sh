#!/usr/bin/env sh

./carthage.sh

carthage checkout
carthage build --platform ios
