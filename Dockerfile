FROM rust:latest

# Install nightly toolchain with rust-src (required for -Zbuild-std on tier 3 targets)
RUN rustup toolchain install nightly --component rust-src

# Install zstd for extracting the OpenWrt SDK
RUN apt-get update && apt-get install -y zstd && rm -rf /var/lib/apt/lists/*

# Download and extract OpenWrt SDK for ath79 (MIPS big-endian, musl)
RUN curl -fsSL https://downloads.openwrt.org/snapshots/targets/ath79/generic/openwrt-sdk-ath79-generic_gcc-14.3.0_musl.Linux-x86_64.tar.zst \
    | zstdcat | tar x -C /opt/ \
    && mv /opt/openwrt-sdk-* /opt/openwrt-sdk

# Generate cargo config with paths from the OpenWrt SDK toolchain
# Dynamically discovers the toolchain dir, target triple, and GCC version
RUN TOOLCHAIN_DIR=$(ls -d /opt/openwrt-sdk/staging_dir/toolchain-mips_*_musl) && \
    TRIPLE=$(ls "$TOOLCHAIN_DIR/lib/gcc/") && \
    GCC_VERSION=$(ls "$TOOLCHAIN_DIR/lib/gcc/$TRIPLE/") && \
    printf '[target.mips-unknown-linux-musl]\n\
linker = "rust-lld"\n\
rustflags = [\n\
    "-C", "target-feature=+soft-float",\n\
    "-C", "linker-flavor=ld.lld",\n\
    "-C", "link-arg=-L%s/%s/lib",\n\
    "-C", "link-arg=-L%s/lib/gcc/%s/%s",\n\
]\n' "$TOOLCHAIN_DIR" "$TRIPLE" "$TOOLCHAIN_DIR" "$TRIPLE" "$GCC_VERSION" > /usr/local/cargo/config.toml

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
