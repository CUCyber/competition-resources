# Windows
This directory contains all useful files, scripts, and tools for Windows.
## Windows Binaries (`./bin`)
### loki-rs
- https://github.com/Neo23x0/Loki-RS
- `loki-util.exe`:
  - SHA256: `AA7E0650EA701A272EF0BE963E5C0554089DF88BC168F1049481BA06D1841119`
- `loki.exe`:
  - SHA256: `67FD9534F75DA1C4D9B34688842C3CD0F35C644F36895159ED75589FDDC6CCFE`
- Build Instructions (Linux Cross Compile):
```
sudo apt-get install -y automake libtool make gcc pkg-config flex bison clang mingw-w64 wget git

# Create symlinks for Windows libraries with case-sensitive names
# Linux is case-sensitive but Windows library names are case-insensitive
cd /usr/x86_64-w64-mingw32/lib
sudo ln -sf libiphlpapi.a libIphlpapi.a
sudo ln -sf libws2_32.a libWs2_32.a
sudo ln -sf libadvapi32.a libAdvapi32.a
sudo ln -sf libkernel32.a libKernel32.a
sudo ln -sf libuser32.a libUser32.a
sudo ln -sf libuserenv.a libUserenv.a
sudo ln -sf libbcrypt.a libBcrypt.a
sudo ln -sf libntdll.a libNtdll.a

rustup target add x86_64-pc-windows-gnu
cargo build --target x86_64-pc-windows-gnu --release --verbose
```
### Bluespawn
- https://github.com/ION28/BLUESPAWN
- `BLUESPAWN-client-x64.exe`
  - SHA256 `837B6D827746B9201EC8623008C9E69F3ECE532C65484AEE169F1EE9F5B8F245`
- Build Instructions (VS2019 Build Tools):
```
git clone https://github.com/ION28/BLUESPAWN.git
cd BLUESPAWN
git submodule update --init --recursive
cd vcpkg
.\bootstrap-vcpkg.bat
.\vcpkg.exe install @../vcpkg_response_file.txt
.\vcpkg.exe integrate install
cd ..
msbuild
```
