# Linux
This directory contains all useful files, scripts, and tools for Linux.

## Linux Binaries (`./bin`)
### `abduco`
- statically linked
- stripped and repacked with UPX
- SHA256: `8a9c02899294efb59f9dbc7713d09b1edb4c0c4184387b7b234856565afe0b03`
- MD5: `7de941d997a6589ab748ae82a13915f7`

```sh
git clone --depth=1 https://github.com/martanne/abduco
sed -i 's/^\(CFLAGS_STD ?= .*\)/\1 -static/' Makefile
make
strip abduco && upx abduco
```

### `busybox`
- compiled with build config included in repo at `/linux/other/.config`
- stripped and repacked with UPX
- SHA256: `2ed40a3ad69e8e3794d2e1093a5def735f4dc7909ef91b99a5984ab55804cf6c`
- MD5: `997cfe6ef993083aca80a1bd0286c910`

```sh
git clone --depth=1 git://git.busybox.net/busybox
mv ../other/.config busybox # build config is included in this repo at /linux/other/.config
make
strip busybox && upx busybox
```

### `dropbear`
- patched with [`dropbear-hacks`](https://github.com/zcutlip/dropbear-hacks/raw/master/hacks_to_dropbear-2016.74.patch)
- stripped and repacked with UPX
- SHA256: `3397ed2266d6ef93862047cc908f54ca1a72a3786c8229175bda105e1bb3aedc`
- MD5: `5afcdc6e13f3be41dbe9a928160f60dd`

```sh
git clone --depth=1 https://github.com/mkj/dropbear
curl -LO https://github.com/zcutlip/dropbear-hacks/raw/master/hacks_to_dropbear-2016.74.patch
patch -p1 <hacks_to_dropbear-2016.74.patch
./configure --enable-static
make PROGRAMS='dropbear dbclient' MULTI=1
strip dropbearmulti && upx dropbearmulti
```

### `fzy`
- statically linked, modified default line number and show info toggle
- stripped and repacked with UPX
- SHA256: `c4732062eceeb3e4fcf43fb31ea440cc5ecd1c9bba8a4a48881acfacc5a0d6aa`
- MD5: `0ea81aeb273d4aa1d649036197563474`

```sh
git clone --depth=1 https://github.com/jhawthorn/fzy
sed -i 's/^\(CFLAGS+=.*\)/\1 -static/' Makefile
sed -i -e 's/^\(#define DEFAULT_NUM_LINES\) 10/\1 20/' -e 's/^\(#define DEFAULT_SHOW_INFO\) 0/\1 1/' src/config.def.h
make
strip fzy && upx fzy
```

### `nethogs`
- statically linked
- stripped and repacked with UPX
- SHA256: `2dfd346945e680ead68d2e005ce7e79eb724fff1371244e1c52533c139493fa6`
- MD5: `b740ccec6862f5cb5f8f61a26f325956`

```sh
git clone --depth=1 https://github.com/raboof/nethogs
sed -i -e 's/^\(CFLAGS+=.*\)/\1 -static/' -e 's/^\(CXXFLAGS+=.*\)/\1 -static/' src/MakeApp.mk
make
strip nethogs && upx nethogs
```

### `nnn`
- disabled X11 integration (set `O_NOX11 := 1` in Makefile) and statically linked
- stripped and repacked with UPX
- SHA256: `427e361b81386076dd422bc519059a7237b9a9eb610d79838e868b3a9b0e1622`
- MD5: `b41e6d3cfbe3e6b6ae35974bb7807dad`

```sh
git clone --depth=1 https://github.com/jarun/nnn
sed -i 's/\(O_NOX11 :=\) 0/\1 1/' Makefile
make O_STATIC=1 strip
upx nnn
```

### `perl`
- [existing build from pts](https://github.com/pts/staticperl/releases/download/v2/staticperl-5.10.1.v2)
- stripped and repacked with UPX
- SHA256: `f69eb152e61d26a5195a4ca80c1f2baaacd16fb7e56ea0134427dd9035e5afc0`
- MD5: `7010dcdf1fe7af14404d3bef4b5b8053`

```sh
curl -L https://github.com/pts/staticperl/releases/download/v2/staticperl-5.10.1.v2 -o perl
strip perl && upx perl
```

### `yr`
- stripped and repacked with UPX
- SHA256: `0d13ebfe01f99214a2eaabc94c69c72f213e7bc8cc19f0fd9c54377d1d09d74f`
- MD5: `127776ccdd06cfe878c8042dece9c3f2`

```sh
git clone --depth=1 https://github.com/VirusTotal/yara-x
cargo build --bin yr --target=x86_64-unknown-linux-musl --release --frozen
strip yr && upx yr
```

### Loki-RS
- Loki SHA256: `117d0bff2048f2a394f379ae55685b3d2da54002431d3f6ee92140ef11089227`
- loki MD5: `50aa71fef2588c3cd2714f98f704b37a`
- loki-util SHA256: `d52c947a79cc3ebaf75b277b15cf69e2ab5dc70b748b08674afc24d2573e367d`
- loki-util MD5: `9539b007790b93f7da03e6099273a1a0`

```sh
# Download Instructions
curl -LO https://github.com/Neo23x0/Loki-RS/releases/download/v2.10.0/loki-linux-x86_64-v2.10.0.tar.gz
tar -xzvf loki-linux-*.tar.gz
./loki-util update
sudo ./loki

# Build Instructions
git clone https://github.com/Neo23x0/Loki-RS/archive/refs/tags/v2.10.0.tar.gz
cargo build
```

### Oryx
- SHA256: `f82821b1baa63a5645a38b2e3e9983f38ffa71ae5925b86e7207bb3c82bd0eaa`
- MD5: `39dd77d249fa65c90cfb483224858323`

```sh
# Download Instructions
curl -LO https://github.com/pythops/oryx/releases/download/v0.8.0/oryx-x86_64-unknown-linux-musl
chmod u+x oryx-x86_64-unknown-linux-musl
./oryx-x86_64-unknown-linux-musl

# Build Instructions
git clone https://github.com/pythops/oryx
rustup toolchain install nightly --component rust-src
# Install bpf-linker (https://github.com/aya-rs/bpf-linker)
# Check bpf-linker Installation section (https://github.com/aya-rs/bpf-linker?tab=readme-ov-file#installation) .
cargo xtask build --release
```
