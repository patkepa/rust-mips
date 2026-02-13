FROM rust:latest

# Install nightly toolchain with rust-src (required for -Zbuild-std on tier 3 targets)
RUN rustup toolchain install nightly --component rust-src

# Download and install MIPS cross-toolchain from musl.cc
RUN curl -fsSL https://musl.cc/mips-linux-musl-cross.tgz | tar xz -C /opt/

# Generate cargo config with Docker-correct paths, dynamically discovering GCC version
RUN GCC_VERSION=$(ls /opt/mips-linux-musl-cross/lib/gcc/mips-linux-musl/) && \
    printf '[target.mips-unknown-linux-musl]\n\
linker = "rust-lld"\n\
rustflags = [\n\
    "-C", "target-feature=+soft-float",\n\
    "-C", "linker-flavor=ld.lld",\n\
    "-C", "link-arg=-L/opt/mips-linux-musl-cross/mips-linux-musl/lib",\n\
    "-C", "link-arg=-L/opt/mips-linux-musl-cross/lib/gcc/mips-linux-musl/%s",\n\
]\n' "$GCC_VERSION" > /usr/local/cargo/config.toml

WORKDIR /usr/src/app

# Phase 1: Build std with a dummy project (cached layer)
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo 'fn main() {}' > src/main.rs
RUN cargo +nightly build -Zbuild-std --target mips-unknown-linux-musl --release 2>&1 || true
# Clean the dummy build artifacts but keep the cached std
RUN rm -rf src target/mips-unknown-linux-musl/release/deps/rust_test_mips* \
    target/mips-unknown-linux-musl/release/rust-test-mips*

# Phase 2: Copy real source and build
COPY src/ src/
RUN cargo +nightly build -Zbuild-std --target mips-unknown-linux-musl --release
