# Generated gRPC stubs

This directory holds the Dart gRPC/protobuf code generated from
`../../../../proto/connectible.proto`. It is **not** checked in as
hand-written source; regenerate it with:

```sh
# from mobile/
dart pub global activate protoc_plugin 21.1.2
export PATH="$PATH:$HOME/.pub-cache/bin"
./tool/gen_proto.sh
```

That produces:

- `connectible.pb.dart`      - message types (Identity, SyncFrame, ...)
- `connectible.pbenum.dart`  - enums (Platform, MouseButton, ErrorCode, ...)
- `connectible.pbgrpc.dart`  - `ConnectibleClient` + service base
- `connectible.pbjson.dart`  - JSON descriptors

`lib/src/services/*.dart` and `lib/src/state/*.dart` import from
`connectible.pbgrpc.dart`, so the app will not compile until these are
generated.
