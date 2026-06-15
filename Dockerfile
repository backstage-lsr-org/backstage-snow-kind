# =============================================================================
#  ⚠️  DO NOT run `docker build .` on this file directly.
#
#  The Backstage backend must be compiled on the host first.
#  Use build.sh instead:
#
#    ./build.sh                          # build local image
#    ./build.sh --push yourname/bs-poc   # build + push to DockerHub
#
#  build.sh scaffolds Backstage, runs yarn build:backend, then creates its
#  own Dockerfile (Dockerfile.snow) inside .backstage-app/ and builds from there.
# =============================================================================

# This is a placeholder — build.sh writes the real Dockerfile.snow
# into .backstage-app/ and runs docker build from that directory.
FROM alpine:3.19
RUN echo "ERROR: Use ./build.sh to build this image, not docker build directly." && \
    echo "See README.md for instructions." && \
    exit 1
