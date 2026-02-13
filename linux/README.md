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

### `loki/`
- statically linked build
- stripped and repacked with UPX
- `loki`
    + SHA256: `d1cc328babf5bf623f79c323770aab372e3537ad1d5469fb8014f6b4d1be50b1`
    + MD5: `ad6aa7fa6bce20b1650742da7d3d8c46`
- `loki-util`
    + SHA256: `9d8ef4cc1040932cb16bf6bade1bb4caf97bf7d6b547e31d70fd1900818cd565`
    + MD5: `368df6e21f8f9b11e6c194629217e1b0`

```sh
git clone --depth=1 https://github.com/Neo23x0/Loki-RS
cargo build --target=x86_64-unknown-linux-musl --release
strip loki loki-util && upx loki loki-util
```

### `oryx`
- [existing build from pythops](https://github.com/pythops/oryx/releases/download/v0.8.0/oryx-x86_64-unknown-linux-musl)
- stripped and repacked with UPX
- SHA256: `512109b648b7c753604208217e4fd59a34f149e577ca766c1ee914a38d32c619`
- MD5: `476775a8544c925b7f42265027383e8e`

```sh
curl -L https://github.com/pythops/oryx/releases/download/v0.8.0/oryx-x86_64-unknown-linux-musl -o oryx
chmod +x oryx
strip oryx && upx oryx
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
cargo build --bin yr --target=x86_64-unknown-linux-musl --release
strip yr && upx yr
```
