#!/usr/bin/env bash
# Regenerates the Dart gRPC stubs from the shared connectible.proto into
# lib/src/generated. Requires the Dart protoc plugin, PINNED to 21.1.2 --
# newer protoc_plugin (>=22) generates code for protobuf >=6.0.0, which
# is incompatible with the grpc 3.x runtime this app pins (grpc 3.x needs
# protobuf 3.x). Keep this version in lockstep with pubspec's protobuf.
#
#   dart pub global activate protoc_plugin 21.1.2
#   export PATH="$PATH:$HOME/.pub-cache/bin"
#
# and protoc on PATH. Run from the mobile/ directory:
#
#   ./tool/gen_proto.sh
set -euo pipefail

PROTO_DIR="../proto"
OUT_DIR="lib/src/generated"

mkdir -p "$OUT_DIR"

protoc \
  --dart_out=grpc:"$OUT_DIR" \
  --proto_path="$PROTO_DIR" \
  "$PROTO_DIR/connectible.proto"

echo "Generated Dart stubs into $OUT_DIR"
