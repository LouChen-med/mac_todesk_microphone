#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
if [[ ! -x ./audio-tools/audio_route || ./src/audio_route.swift -nt ./audio-tools/audio_route ]]; then
    /bin/bash ./scripts/build.sh
fi
./audio-tools/audio_route restore-output
