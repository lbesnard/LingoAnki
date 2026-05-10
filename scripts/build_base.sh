#!/usr/bin/env bash
# Build and push the LingoAnki base Docker image to Docker Hub.
#
# The base stage is defined inside the main Dockerfile (multi-stage build).
# This script builds only that stage and tags it as a standalone image so
# CI/CD runners can pull it and skip the slow ML install on every app build.
#
# Run this ONLY when you need to upgrade the heavy ML packages
# (torch, openai-whisper, spacy, piper-tts, ovos-tts-plugin-piper).
# Normal app rebuilds: docker compose up --build -d  (no push needed)
#
# Usage:
#   bash scripts/build_base.sh             # build + push latest
#   bash scripts/build_base.sh --no-push   # build only (no push)

set -euo pipefail

REPO="lozzaroo/lingodiary-base"
TAG="latest"
PUSH=true

for arg in "$@"; do
    case "$arg" in
        --no-push) PUSH=false ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo "==> Building base stage from Dockerfile: ${REPO}:${TAG}"
echo "    This installs torch, whisper, spacy, piper-tts — expect 10-20 min on first build."
echo ""

docker build \
    --target base \
    --tag "${REPO}:${TAG}" \
    .

if [ "$PUSH" = true ]; then
    echo ""
    echo "==> Pushing ${REPO}:${TAG} to Docker Hub (~10 GB upload, be patient)..."
    docker push "${REPO}:${TAG}"
    echo ""
    echo "Done! Normal app rebuilds (docker compose up --build) will be fast."
else
    echo ""
    echo "Done! Run 'docker push ${REPO}:${TAG}' to push when ready."
fi
