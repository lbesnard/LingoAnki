#!/usr/bin/env bash
# Build and push the LingoAnki base Docker image.
#
# Run this ONLY when you need to upgrade the heavy ML packages
# (torch, openai-whisper, spacy, piper-tts, ovos-tts-plugin-piper).
# Normal app rebuilds use `docker build .` (the main Dockerfile) which
# is fast and pushes only ~1-2 GB instead of ~10 GB.
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

echo "==> Building base image: ${REPO}:${TAG}"
echo "    This installs torch, whisper, spacy, piper-tts — expect 10-20 min on first build."
echo ""

docker build \
    --file Dockerfile.base \
    --tag "${REPO}:${TAG}" \
    .

if [ "$PUSH" = true ]; then
    echo ""
    echo "==> Pushing ${REPO}:${TAG} to Docker Hub (~10 GB upload, be patient)..."
    docker push "${REPO}:${TAG}"
    echo ""
    echo "Done! Normal app builds (docker build .) will now be fast (~1-2 GB push)."
else
    echo ""
    echo "Done! Run 'docker push ${REPO}:${TAG}' to push when ready."
fi
