fn main() {
    println!("cargo:rerun-if-changed=../proto/connectible.proto");
    tonic_prost_build::configure()
        .build_server(true)
        .build_client(true)
        .compile_protos(&["../proto/connectible.proto"], &["../proto"])
        .expect("failed to compile connectible.proto");
}
