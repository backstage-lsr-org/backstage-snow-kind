# ⚠️  DO NOT run `docker build .` on this file directly.
#
# The Backstage backend must be compiled on the HOST before Docker runs,
# because `yarn build:backend` requires the full yarn workspace.
#
# Use build.sh instead:
#   ./build.sh                          # local image
#   ./build.sh --push yourname/bs-poc   # build + push to DockerHub
#
# build.sh will scaffold Backstage, build it, then write and use its own
# Dockerfile (Dockerfile.snow) inside .backstage-app/.

FROM scratch
RUN echo "Run ./build.sh instead of docker build directly" && exit 1
