# z-scripts.nix — Bootstrap scripts for building Nix on s390x (Ubuntu 22.04).
#
# Each script is defined as { name, text, needsEnv?, description } and produces:
#   - check: writeShellApplication derivation (shellcheck at build time)
#   - script: writeTextFile with #!/usr/bin/env bash (runs on z without Nix)
#
# 19-shellcheck.sh and sync-to-z.sh are superseded by nix flake check / nix run .#sync.
{ pkgs }:

let
  versions = import ./z-scripts/versions.nix;
  envSetup = import ./z-scripts/env.nix;

  # Build a z-deployable script with shellcheck validation.
  mkZScript = { name, text, needsEnv ? false, description ? "" }:
    let
      body = (if needsEnv then envSetup else "") + text;
    in {
      check = pkgs.writeShellApplication {
        name = "check-${name}";
        text = body;
      };
      script = pkgs.writeTextFile {
        name = "${name}.sh";
        executable = true;
        text = "#!/usr/bin/env bash\nset -euo pipefail\n\n" + body;
      };
    };

  scriptDefs = {

    # --- 00: APT dependencies ---
    "00-apt-deps" = mkZScript {
      name = "00-apt-deps";
      description = "Install Ubuntu 22.04 packages needed to bootstrap Nix on s390x";
      text = ''
        # Install Ubuntu 22.04 packages needed to bootstrap Nix on s390x.
        # Run as root: sudo bash 00-apt-deps.sh
        #
        # These satisfy ~10 of Nix's build dependencies directly.
        # The remaining deps (GCC 14, Boost 1.87, nlohmann_json 3.11,
        # toml11 4.x, SQLite 3.49, Boehm GC 8.2, curl 8.17, libgit2 1.9,
        # libseccomp 2.5.5, BLAKE3 1.8) are built from source in later phases.

        if [[ $EUID -ne 0 ]]; then
            echo "error: must run as root (use sudo)" >&2
            exit 1
        fi

        apt-get update

        # Remove busybox-static if present — Ubuntu's busybox doesn't work
        # in the Nix store (argv[0] applet lookup fails), and its presence
        # causes meson to set sandbox_shell, making tests fail instead of skip.
        apt-get remove -y busybox-static 2>/dev/null || true

        apt-get install -y \
            ninja-build \
            pkg-config \
            bison \
            flex \
            libsqlite3-dev \
            libsodium-dev \
            libarchive-dev \
            libssl-dev \
            libbrotli-dev \
            libreadline-dev \
            libedit-dev \
            cmake \
            autoconf \
            automake \
            libtool \
            gperf \
            python3-pip \
            texinfo \
            libgmp-dev \
            libmpfr-dev \
            libmpc-dev \
            wget \
            xz-utils \
            zlib1g-dev \
            git \
            m4 \
            gettext \
            lowdown \
            bash-static

        echo "Phase 0 complete: apt dependencies installed."
      '';
    };

    # --- 01: Meson via pip ---
    "01-meson-pip" = mkZScript {
      name = "01-meson-pip";
      description = "Install meson >= 1.1 via pip";
      text = ''
        # Install meson >= 1.1 via pip (Ubuntu 22.04 ships 0.61).

        pip3 install --user meson

        MESON_BIN="''${HOME}/.local/bin/meson"

        if [[ -x "$MESON_BIN" ]]; then
            echo "meson installed: $("$MESON_BIN" --version)"
        else
            echo "error: meson not found at $MESON_BIN" >&2
            exit 1
        fi

        echo "Phase 1 complete: meson installed via pip."
      '';
    };

    # --- 02: GCC 14 ---
    "02-gcc14" = mkZScript {
      name = "02-gcc14";
      description = "Build GCC ${versions.gcc.version} from source for C++23 support";
      text = let v = versions.gcc; in ''
        # Build GCC ${v.version} from source for C++23 support.
        # This is the longest phase (~1-3 hours on s390x).

        GCC_VERSION="${v.version}"
        GCC_URL="${v.url}"
        BUILD_DIR="''${HOME}/gcc-build"
        SRC_DIR="''${BUILD_DIR}/gcc-''${GCC_VERSION}"
        OBJ_DIR="''${BUILD_DIR}/objdir"
        PREFIX="/usr/local"
        JOBS=1  # z machine has only 3.9 GiB RAM; >1 job OOMs during linking

        # Skip if correct version is already installed
        if "''${PREFIX}/bin/gcc" --version 2>/dev/null | head -n 1 | grep -q "''${GCC_VERSION}"; then
            echo "GCC ''${GCC_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "gcc-''${GCC_VERSION}.tar.xz" ]]; then
            echo "Downloading GCC ''${GCC_VERSION}..."
            wget -q "$GCC_URL"
        fi

        if [[ ! -d "$SRC_DIR" ]]; then
            echo "Extracting..."
            tar xf "gcc-''${GCC_VERSION}.tar.xz"
        fi

        cd "$SRC_DIR"
        echo "Downloading prerequisites..."
        ./contrib/download_prerequisites

        mkdir -p "$OBJ_DIR"
        cd "$OBJ_DIR"

        echo "Configuring GCC ''${GCC_VERSION} (languages: c,c++)..."
        "''${SRC_DIR}/configure" \
            --prefix="$PREFIX" \
            --enable-languages=c,c++ \
            --disable-multilib \
            --disable-bootstrap \
            --disable-nls \
            --with-system-zlib

        echo "Building GCC ''${GCC_VERSION} with ''${JOBS} jobs..."
        make -j "$JOBS"

        echo "Installing GCC ''${GCC_VERSION} to ''${PREFIX}..."
        sudo make install

        echo "Updating shared library cache..."
        sudo ldconfig

        echo "Phase 2 complete: GCC ''${GCC_VERSION} installed."
        "''${PREFIX}/bin/gcc" --version
      '';
    };

    # --- 03: Environment (sourced, not executed) ---
    "03-env" = mkZScript {
      name = "03-env";
      description = "Environment setup for building dependencies and Nix with GCC 14";
      text = ''
        # Source this file, do not execute it: source 03-env.sh
        #
        # Sets up the environment for building dependencies and Nix with GCC 14.
        # Source this after phase 2 (GCC 14) and before every subsequent phase.
      '' + envSetup + ''
        echo "Environment configured for Nix s390x build."
        echo "  CC=$CC"
        echo "  CXX=$CXX"
        echo "  PATH includes: /usr/local/bin, ~/.local/bin"
      '';
    };

    # --- 04: Boost ---
    "04-boost" = mkZScript {
      name = "04-boost";
      needsEnv = true;
      description = "Build Boost ${versions.boost.version} from source using GCC 14";
      text = let v = versions.boost; in ''
        # Build Boost ${v.version} from source using GCC 14.
        # Ubuntu 22.04 ships Boost 1.74 which is too old for Nix.

        BOOST_VERSION="${v.version}"
        BOOST_UNDERSCORE="${v.underscore}"
        BOOST_URL="${v.url}"
        BUILD_DIR="''${HOME}/boost-build"
        PREFIX="/usr/local"
        JOBS=1  # z machine has only 3.9 GiB RAM; >1 job OOMs during linking

        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++

        # Skip if correct version is already installed
        if [[ -f "''${PREFIX}/include/boost/version.hpp" ]] && \
           grep -q "BOOST_LIB_VERSION \"''${BOOST_UNDERSCORE}\"" "''${PREFIX}/include/boost/version.hpp" 2>/dev/null; then
            echo "Boost ''${BOOST_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "boost_''${BOOST_UNDERSCORE}.tar.bz2" ]]; then
            echo "Downloading Boost ''${BOOST_VERSION}..."
            wget -q "$BOOST_URL"
        fi

        if [[ ! -d "boost_''${BOOST_UNDERSCORE}" ]]; then
            echo "Extracting..."
            tar xf "boost_''${BOOST_UNDERSCORE}.tar.bz2"
        fi

        cd "boost_''${BOOST_UNDERSCORE}"

        echo "Bootstrapping Boost build system..."
        ./bootstrap.sh --prefix="$PREFIX" --with-toolset=gcc

        echo "Building and installing Boost ''${BOOST_VERSION} with ''${JOBS} jobs..."
        # Note: install requires sudo because --prefix=/usr/local
        sudo LD_LIBRARY_PATH="/usr/local/lib64:/usr/local/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
            ./b2 -j "$JOBS" \
            toolset=gcc \
            cxxflags="-std=c++17" \
            link=shared,static \
            threading=multi \
            variant=release \
            install --prefix="$PREFIX"

        sudo ldconfig

        echo "Phase 4 complete: Boost ''${BOOST_VERSION} installed."
      '';
    };

    # --- 05: nlohmann_json ---
    "05-nlohmann-json" = mkZScript {
      name = "05-nlohmann-json";
      description = "Install nlohmann_json ${versions.nlohmann-json.version} from source";
      text = let v = versions.nlohmann-json; in ''
        # Install nlohmann_json ${v.version} from source.
        # Ubuntu 22.04 ships 3.10.5 which fails to compile with GCC 14
        # due to stricter C++23 implicit conversion rules in std::pair.

        NLOHMANN_VERSION="${v.version}"
        NLOHMANN_URL="${v.url}"
        BUILD_DIR="''${HOME}/nlohmann-build"
        PREFIX="/usr/local"

        # Skip if correct version is already installed
        if pkg-config --exact-version="''${NLOHMANN_VERSION}" nlohmann_json 2>/dev/null; then
            echo "nlohmann_json ''${NLOHMANN_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "json.tar.xz" ]]; then
            echo "Downloading nlohmann_json ''${NLOHMANN_VERSION}..."
            wget -q "$NLOHMANN_URL"
        fi

        if [[ ! -d "json" ]]; then
            echo "Extracting..."
            tar xf "json.tar.xz"
        fi

        mkdir -p "json/build"
        cd "json/build"

        echo "Configuring nlohmann_json ''${NLOHMANN_VERSION}..."
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DJSON_BuildTests=OFF

        echo "Installing nlohmann_json ''${NLOHMANN_VERSION}..."
        sudo cmake --install .

        echo "Phase 5 complete: nlohmann_json ''${NLOHMANN_VERSION} installed."
      '';
    };

    # --- 06: toml11 ---
    "06-toml11" = mkZScript {
      name = "06-toml11";
      description = "Install toml11 ${versions.toml11.version} from source";
      text = let v = versions.toml11; in ''
        # Install toml11 ${v.version} from source.
        # Ubuntu 22.04's libtoml11-dev (3.7.0) lacks cmake config files,
        # so meson's cmake dependency detection cannot find it.

        TOML11_VERSION="${v.version}"
        TOML11_URL="${v.url}"
        BUILD_DIR="''${HOME}/toml11-build"
        PREFIX="/usr/local"

        # Skip if correct version is already installed
        if [[ -f "''${PREFIX}/lib/cmake/toml11/toml11Config.cmake" ]] && \
           grep -q "''${TOML11_VERSION}" "''${PREFIX}/lib/cmake/toml11/toml11ConfigVersion.cmake" 2>/dev/null; then
            echo "toml11 ''${TOML11_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -d "toml11" ]]; then
            echo "Cloning toml11 ''${TOML11_VERSION}..."
            git clone --depth 1 --branch "v''${TOML11_VERSION}" "$TOML11_URL"
        fi

        mkdir -p "toml11/build"
        cd "toml11/build"

        echo "Configuring toml11 ''${TOML11_VERSION}..."
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$PREFIX"

        echo "Installing toml11 ''${TOML11_VERSION}..."
        sudo cmake --install .

        echo "Phase 6 complete: toml11 ''${TOML11_VERSION} installed."
      '';
    };

    # --- 07: SQLite ---
    "07-sqlite" = mkZScript {
      name = "07-sqlite";
      description = "Build SQLite ${versions.sqlite.display} from source";
      text = let v = versions.sqlite; in ''
        # Build SQLite ${v.display} from source.
        # Ubuntu 22.04 ships 3.37.2 which lacks sqlite3_error_offset()
        # (added in 3.38.0), required by Nix's sqlite.cc.

        SQLITE_VERSION="${v.version}"
        SQLITE_URL="${v.url}"
        BUILD_DIR="''${HOME}/sqlite-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        # Skip if correct version is already installed
        if "''${PREFIX}/bin/sqlite3" --version 2>/dev/null | grep -q "${v.display}"; then
            echo "SQLite ${v.display} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "sqlite-autoconf-''${SQLITE_VERSION}.tar.gz" ]]; then
            echo "Downloading SQLite ''${SQLITE_VERSION}..."
            wget -q "$SQLITE_URL"
        fi

        if [[ ! -d "sqlite-autoconf-''${SQLITE_VERSION}" ]]; then
            echo "Extracting..."
            tar xf "sqlite-autoconf-''${SQLITE_VERSION}.tar.gz"
        fi

        cd "sqlite-autoconf-''${SQLITE_VERSION}"

        echo "Configuring SQLite..."
        ./configure --prefix="$PREFIX"

        echo "Building SQLite with ''${JOBS} jobs..."
        make -j "$JOBS"

        echo "Installing SQLite..."
        sudo make install
        sudo ldconfig

        echo "Phase 7 complete: SQLite ''${SQLITE_VERSION} installed."
        "''${PREFIX}/bin/sqlite3" --version
      '';
    };

    # --- 08: Boehm GC ---
    "08-boehm-gc" = mkZScript {
      name = "08-boehm-gc";
      description = "Build Boehm GC ${versions.boehm-gc.version} from source with C++ support";
      text = let v = versions.boehm-gc; in ''
        # Build Boehm GC ${v.version} from source with C++ support.
        # Ubuntu 22.04 ships 8.0.6 where traceable_allocator<void>::value_type
        # is private, causing compilation failures with Boost 1.87's
        # container::allocator_traits. Fixed in 8.2.x.

        GC_VERSION="${v.version}"
        GC_URL="${v.url}"
        ATOMICOPS_URL="${v.atomicops-url}"
        BUILD_DIR="''${HOME}/bdwgc-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        # Skip if correct version is already installed
        if pkg-config --atleast-version="''${GC_VERSION}" bdw-gc 2>/dev/null; then
            echo "Boehm GC ''${GC_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -d "bdwgc" ]]; then
            echo "Cloning Boehm GC ''${GC_VERSION}..."
            git clone --depth 1 --branch "v''${GC_VERSION}" "$GC_URL"
        fi

        cd bdwgc

        if [[ ! -d "libatomic_ops" ]]; then
            echo "Cloning libatomic_ops..."
            git clone --depth 1 "$ATOMICOPS_URL"
        fi

        rm -rf build
        mkdir build
        cd build

        echo "Configuring Boehm GC ''${GC_VERSION} with C++ support..."
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -Dbuild_tests=OFF \
            -Denable_cplusplus=ON

        echo "Building Boehm GC ''${GC_VERSION} with ''${JOBS} jobs..."
        cmake --build . -j "$JOBS"

        echo "Installing Boehm GC ''${GC_VERSION}..."
        sudo cmake --install .
        sudo ldconfig

        echo "Phase 8 complete: Boehm GC ''${GC_VERSION} installed."
      '';
    };

    # --- 09: curl ---
    "09-curl" = mkZScript {
      name = "09-curl";
      needsEnv = true;
      description = "Build libcurl ${versions.curl.version} from source";
      text = let v = versions.curl; in ''
        # Build libcurl ${v.version} from source.
        # Ubuntu 22.04 ships 7.81. Nix requires >= 8.17.0.

        CURL_VERSION="${v.version}"
        CURL_URL="${v.url}"
        BUILD_DIR="''${HOME}/curl-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++

        # Skip if correct version is already installed
        if "''${PREFIX}/bin/curl" --version 2>/dev/null | head -n 1 | grep -q "''${CURL_VERSION}"; then
            echo "curl ''${CURL_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "curl-''${CURL_VERSION}.tar.xz" ]]; then
            echo "Downloading curl ''${CURL_VERSION}..."
            wget -q "$CURL_URL"
        fi

        if [[ ! -d "curl-''${CURL_VERSION}" ]]; then
            echo "Extracting..."
            tar xf "curl-''${CURL_VERSION}.tar.xz"
        fi

        cd "curl-''${CURL_VERSION}"

        echo "Configuring curl ''${CURL_VERSION}..."
        ./configure \
            --prefix="$PREFIX" \
            --with-openssl \
            --without-libpsl

        echo "Building curl ''${CURL_VERSION} with ''${JOBS} jobs..."
        make -j "$JOBS"

        echo "Installing curl ''${CURL_VERSION}..."
        sudo make install
        sudo ldconfig

        echo "Phase 9 complete: curl ''${CURL_VERSION} installed."
        "''${PREFIX}/bin/curl" --version | head -n 1
      '';
    };

    # --- 10: libgit2 ---
    "10-libgit2" = mkZScript {
      name = "10-libgit2";
      needsEnv = true;
      description = "Build libgit2 ${versions.libgit2.version} from source";
      text = let v = versions.libgit2; in ''
        # Build libgit2 ${v.version} from source (Ubuntu 22.04 has 1.1).

        LIBGIT2_VERSION="${v.version}"
        LIBGIT2_URL="${v.url}"
        BUILD_DIR="''${HOME}/libgit2-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++

        # Skip if correct version is already installed
        if pkg-config --exact-version="''${LIBGIT2_VERSION}" libgit2 2>/dev/null; then
            echo "libgit2 ''${LIBGIT2_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "v''${LIBGIT2_VERSION}.tar.gz" ]]; then
            echo "Downloading libgit2 ''${LIBGIT2_VERSION}..."
            wget -q "$LIBGIT2_URL"
        fi

        if [[ ! -d "libgit2-''${LIBGIT2_VERSION}" ]]; then
            echo "Extracting..."
            tar xf "v''${LIBGIT2_VERSION}.tar.gz"
        fi

        mkdir -p "libgit2-''${LIBGIT2_VERSION}/build"
        cd "libgit2-''${LIBGIT2_VERSION}/build"

        echo "Configuring libgit2 ''${LIBGIT2_VERSION}..."
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_TESTS=OFF

        echo "Building libgit2 ''${LIBGIT2_VERSION} with ''${JOBS} jobs..."
        cmake --build . -j "$JOBS"

        echo "Installing libgit2 ''${LIBGIT2_VERSION}..."
        sudo cmake --install .
        sudo ldconfig

        echo "Phase 10 complete: libgit2 ''${LIBGIT2_VERSION} installed."
      '';
    };

    # --- 11: libseccomp ---
    "11-libseccomp" = mkZScript {
      name = "11-libseccomp";
      needsEnv = true;
      description = "Build libseccomp ${versions.libseccomp.version} from source";
      text = let v = versions.libseccomp; in ''
        # Build libseccomp ${v.version} from source (Ubuntu 22.04 has 2.5.3).

        SECCOMP_VERSION="${v.version}"
        SECCOMP_URL="${v.url}"
        BUILD_DIR="''${HOME}/seccomp-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++

        # Skip if correct version is already installed
        if pkg-config --exact-version="''${SECCOMP_VERSION}" libseccomp 2>/dev/null; then
            echo "libseccomp ''${SECCOMP_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "libseccomp-''${SECCOMP_VERSION}.tar.gz" ]]; then
            echo "Downloading libseccomp ''${SECCOMP_VERSION}..."
            wget -q "$SECCOMP_URL"
        fi

        if [[ ! -d "libseccomp-''${SECCOMP_VERSION}" ]]; then
            echo "Extracting..."
            tar xf "libseccomp-''${SECCOMP_VERSION}.tar.gz"
        fi

        cd "libseccomp-''${SECCOMP_VERSION}"

        echo "Configuring libseccomp ''${SECCOMP_VERSION}..."
        ./configure --prefix="$PREFIX"

        echo "Building libseccomp ''${SECCOMP_VERSION} with ''${JOBS} jobs..."
        make -j "$JOBS"

        echo "Installing libseccomp ''${SECCOMP_VERSION}..."
        sudo make install
        sudo ldconfig

        echo "Phase 11 complete: libseccomp ''${SECCOMP_VERSION} installed."
      '';
    };

    # --- 12: BLAKE3 ---
    "12-blake3" = mkZScript {
      name = "12-blake3";
      needsEnv = true;
      description = "Build BLAKE3 ${versions.blake3.version} C library from source";
      text = let v = versions.blake3; in ''
        # Build BLAKE3 C library from source (not in Ubuntu 22.04).

        BLAKE3_VERSION="${v.version}"
        BLAKE3_URL="${v.url}"
        BUILD_DIR="''${HOME}/blake3-build"
        PREFIX="/usr/local"
        JOBS="$(nproc)"

        export CC=/usr/local/bin/gcc
        export CXX=/usr/local/bin/g++

        # Skip if correct version is already installed
        if pkg-config --exact-version="''${BLAKE3_VERSION}" libblake3 2>/dev/null; then
            echo "BLAKE3 ''${BLAKE3_VERSION} already installed, skipping."
            exit 0
        fi

        mkdir -p "$BUILD_DIR"
        cd "$BUILD_DIR"

        if [[ ! -f "''${BLAKE3_VERSION}.tar.gz" ]]; then
            echo "Downloading BLAKE3 ''${BLAKE3_VERSION}..."
            wget -q "$BLAKE3_URL"
        fi

        if [[ ! -d "BLAKE3-''${BLAKE3_VERSION}" ]]; then
            echo "Extracting..."
            tar xf "''${BLAKE3_VERSION}.tar.gz"
        fi

        mkdir -p "BLAKE3-''${BLAKE3_VERSION}/c/build"
        cd "BLAKE3-''${BLAKE3_VERSION}/c/build"

        echo "Configuring BLAKE3 ''${BLAKE3_VERSION}..."
        cmake .. \
            -DCMAKE_INSTALL_PREFIX="$PREFIX" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBLAKE3_BUILD_SHARED_LIBS=ON

        echo "Building BLAKE3 ''${BLAKE3_VERSION} with ''${JOBS} jobs..."
        cmake --build . -j "$JOBS"

        echo "Installing BLAKE3 ''${BLAKE3_VERSION}..."
        sudo cmake --install .
        sudo ldconfig

        echo "Phase 12 complete: BLAKE3 ''${BLAKE3_VERSION} installed."
      '';
    };

    # --- 13: Nix build ---
    "13-nix-build" = mkZScript {
      name = "13-nix-build";
      needsEnv = true;
      description = "Configure and build Nix from source using meson";
      text = ''
        # Configure and build Nix from source using meson.
        # Run from the nix source directory after sourcing 03-env.sh.

        NIX_SRC="''${HOME}/nix"
        BUILD_DIR="''${NIX_SRC}/build"
        JOBS="$(nproc)"

        if [[ ! -f "''${NIX_SRC}/meson.build" ]]; then
            echo "error: run this script from the nix source directory or set NIX_SRC" >&2
            echo "  expected: ''${NIX_SRC}/meson.build" >&2
            exit 1
        fi

        cd "$NIX_SRC"

        if [[ ! -d "$BUILD_DIR" ]]; then
            echo "Configuring Nix build..."
            meson setup "$BUILD_DIR" \
                --prefix=/usr/local \
                -Ddoc-gen=false \
                -Dunit-tests=false \
                -Dbindings=false \
                -Dbenchmarks=false \
                -Djson-schema-checks=false \
                -Dlibcmd:readline-flavor=readline \
                -Dlibstore:sandbox-shell=/usr/bin/bash-static
        else
            echo "Build directory exists, reconfiguring..."
            meson setup "$BUILD_DIR" --reconfigure \
                --prefix=/usr/local \
                -Ddoc-gen=false \
                -Dunit-tests=false \
                -Dbindings=false \
                -Dbenchmarks=false \
                -Djson-schema-checks=false \
                -Dlibcmd:readline-flavor=readline \
                -Dlibstore:sandbox-shell=/usr/bin/bash-static
        fi

        echo "Building Nix with ''${JOBS} jobs..."
        meson compile -C "$BUILD_DIR" -j "$JOBS"

        echo "Phase 13 complete: Nix built successfully."
        echo "To install: sudo meson install -C ''${BUILD_DIR}"
      '';
    };

    # --- 14: Nix install ---
    "14-nix-install" = mkZScript {
      name = "14-nix-install";
      needsEnv = true;
      description = "Install Nix and set up /nix/store";
      text = ''
        # Install Nix and set up /nix/store.
        # Run as the build user (not root) — uses sudo internally where needed.
        # Meson is installed via pip in ~/.local/bin and needs PYTHONPATH preserved.

        NIX_SRC="''${HOME}/nix"
        BUILD_DIR="''${NIX_SRC}/build"
        PYTHON_SITE="$(python3 -c 'import site; print(site.getusersitepackages())')"

        if [[ ! -d "$BUILD_DIR" ]]; then
            echo "error: build directory not found at ''${BUILD_DIR}" >&2
            echo "  run 13-nix-build.sh first" >&2
            exit 1
        fi

        echo "Installing Nix..."
        sudo env \
            PATH="''${HOME}/.local/bin:''${PATH}" \
            PYTHONPATH="''${PYTHON_SITE}" \
            meson install -C "$BUILD_DIR"

        # Libraries install to /usr/local/lib/s390x-linux-gnu on s390x
        # GCC 14's libstdc++ is in /usr/local/lib64 — must be in ldconfig
        # so the nix binary can find it without LD_LIBRARY_PATH
        echo "/usr/local/lib64" | sudo tee /etc/ld.so.conf.d/gcc14.conf > /dev/null
        echo "/usr/local/lib/s390x-linux-gnu" | sudo tee /etc/ld.so.conf.d/nix.conf > /dev/null
        sudo ldconfig

        echo "Creating /nix/store..."
        sudo mkdir -p /nix/store
        sudo chmod 1775 /nix/store

        echo "Creating nixbld group and users..."
        if ! getent group nixbld > /dev/null 2>&1; then
            sudo groupadd -r nixbld
        fi

        for i in $(seq 1 10); do
            USERNAME="nixbld''${i}"
            if ! id "$USERNAME" > /dev/null 2>&1; then
                sudo useradd -r -g nixbld -G nixbld \
                    -d /var/empty -s /usr/sbin/nologin \
                    -c "Nix build user ''${i}" \
                    "$USERNAME"
            fi
        done

        echo "Setting /nix/store ownership..."
        sudo chown root:nixbld /nix/store

        echo "Phase 14 complete: Nix installed."
        echo "Test with: nix --version"
      '';
    };

    # --- 15: Test dependencies ---
    "15-test-deps" = mkZScript {
      name = "15-test-deps";
      needsEnv = true;
      description = "Install test dependencies (jq, GoogleTest, RapidCheck)";
      text = let vj = versions.jq; vg = versions.googletest; vr = versions.rapidcheck; in ''
        # Install test dependencies for running Nix's unit and functional tests.
        #
        # jq is built from source because Nix's functional tests assume modern
        # tooling (jq >= 1.7 for .[]? try-iterate syntax). Ubuntu 22.04 ships 1.6.
        #
        # GoogleTest and RapidCheck must be built from source because Ubuntu 22.04's
        # versions are incompatible with GCC 14 / C++23.

        PREFIX="/usr/local"
        JOBS="$(nproc)"

        # jq ${vj.version} from source.
        # Nix's functional tests use jq 1.7+ syntax (e.g., '.info.[].ca').
        # Ubuntu 22.04 ships jq 1.6 which does not support this.
        JQ_VERSION="${vj.version}"
        JQ_DIR="''${HOME}/jq-build"

        if ! jq --version 2>/dev/null | grep -q "jq-1\.[7-9]"; then
            echo "Building jq ''${JQ_VERSION}..."
            mkdir -p "$JQ_DIR"
            cd "$JQ_DIR"
            if [[ ! -d "jq" ]]; then
                git clone --depth 1 --branch "jq-''${JQ_VERSION}" ${vj.url}
            fi
            cd jq
            git submodule update --init
            autoreconf -i
            ./configure --with-oniguruma=builtin --prefix="$PREFIX"
            make -j "$JOBS"
            sudo make install
            echo "jq ''${JQ_VERSION} installed."
        else
            echo "jq >= 1.7 already installed, skipping."
        fi

        # GoogleTest ${vg.version} from source.
        # Ubuntu 22.04's GoogleTest 1.11 triggers -Werror=undef with GCC 14
        # (undefined GTEST_OS_WINDOWS_MOBILE macro in gmock-actions.h).
        GTEST_VERSION="${vg.version}"
        GTEST_DIR="''${HOME}/gtest-build"

        if ! pkg-config --atleast-version=1.15 gtest 2>/dev/null; then
            echo "Building GoogleTest ''${GTEST_VERSION}..."
            mkdir -p "$GTEST_DIR"
            cd "$GTEST_DIR"
            if [[ ! -d "googletest" ]]; then
                git clone --depth 1 --branch "v''${GTEST_VERSION}" ${vg.url}
            fi
            cd googletest
            rm -rf build && mkdir build && cd build
            cmake .. -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_BUILD_TYPE=Release
            make -j "$JOBS"
            sudo make install
            echo "GoogleTest ''${GTEST_VERSION} installed."
        else
            echo "GoogleTest already installed, skipping."
        fi

        # RapidCheck from source (nix-on-z fork with -fPIC fix).
        # Ubuntu 22.04's RapidCheck has macro issues with C++23
        # (RC_GTEST_TYPED_FIXTURE_PROP fails to compile).
        # The fork adds CMAKE_POSITION_INDEPENDENT_CODE so the static library can be
        # linked into Nix's shared test-support libraries without text relocations,
        # which cause SIGSEGV on s390x.
        RC_DIR="''${HOME}/rapidcheck-build"

        if [[ ! -f "''${PREFIX}/lib/pkgconfig/rapidcheck.pc" ]] || \
           ! grep -q "''${PREFIX}" "''${PREFIX}/lib/pkgconfig/rapidcheck.pc" 2>/dev/null; then
            echo "Building RapidCheck from source (nix-on-z fork)..."
            mkdir -p "$RC_DIR"
            cd "$RC_DIR"
            if [[ ! -d "rapidcheck" ]]; then
                git clone --depth 1 --branch ${vr.branch} ${vr.url}
            fi
            cd rapidcheck
            rm -rf build && mkdir build && cd build
            cmake .. \
                -DCMAKE_INSTALL_PREFIX="$PREFIX" \
                -DCMAKE_BUILD_TYPE=Release \
                -DRC_ENABLE_GTEST=ON \
                -DRC_ENABLE_GMOCK=ON \
                -DCMAKE_POSITION_INDEPENDENT_CODE=ON
            make -j "$JOBS"
            sudo make install
            # RapidCheck's cmake install produces a .pc file with an empty Libs: line,
            # so meson falls back to finding the system librapidcheck.a at
            # /usr/lib/s390x-linux-gnu/. Replace it with our PIC-built version.
            if [[ -f /usr/lib/s390x-linux-gnu/librapidcheck.a ]]; then
                sudo cp "''${PREFIX}/lib/librapidcheck.a" /usr/lib/s390x-linux-gnu/librapidcheck.a
                echo "Replaced system librapidcheck.a with PIC version."
            fi
            echo "RapidCheck installed."
        else
            echo "RapidCheck already installed, skipping."
        fi

        echo "Phase 15 complete: test dependencies installed."
      '';
    };

    # --- 16: Nix build with tests ---
    "16-nix-build-tests" = mkZScript {
      name = "16-nix-build-tests";
      needsEnv = true;
      description = "Rebuild Nix with unit tests enabled";
      text = ''
        # Rebuild Nix with unit tests enabled, then run them.
        # Run after sourcing 03-env.sh.

        NIX_SRC="''${HOME}/nix"
        BUILD_DIR="''${NIX_SRC}/build"
        JOBS="$(nproc)"

        cd "$NIX_SRC"

        # Reconfigure with unit tests enabled
        echo "Reconfiguring Nix with unit tests enabled..."
        if [[ -d "$BUILD_DIR" ]]; then
            meson setup "$BUILD_DIR" --reconfigure \
                --prefix=/usr/local \
                -Ddoc-gen=false \
                -Dunit-tests=true \
                -Dbindings=false \
                -Dbenchmarks=false \
                -Djson-schema-checks=false \
                -Dlibcmd:readline-flavor=readline \
                -Dlibstore:sandbox-shell=/usr/bin/bash-static
        else
            meson setup "$BUILD_DIR" \
                --prefix=/usr/local \
                -Ddoc-gen=false \
                -Dunit-tests=true \
                -Dbindings=false \
                -Dbenchmarks=false \
                -Djson-schema-checks=false \
                -Dlibcmd:readline-flavor=readline \
                -Dlibstore:sandbox-shell=/usr/bin/bash-static
        fi

        echo "Building Nix (with tests) using ''${JOBS} jobs..."
        meson compile -C "$BUILD_DIR" -j "$JOBS"

        echo "Phase 16 complete: Nix built with unit tests."
        echo "Run tests with: meson test -C ''${BUILD_DIR}"
      '';
    };

    # --- 17: Run tests ---
    "17-run-tests" = mkZScript {
      name = "17-run-tests";
      needsEnv = true;
      description = "Run all Nix test suites and capture results";
      text = ''
        # Run all Nix test suites and capture results.
        # Run after 16-nix-build-tests.sh completes.
        #
        # Prerequisites:
        #   - jq >= 1.7 (built in 15-test-deps.sh)
        #   - bash-static (installed in 00-apt-deps.sh, used as sandbox shell)
        #   - 18-verify-test-env.sh passed (optional but recommended)

        NIX_SRC="''${HOME}/nix"
        BUILD_DIR="''${NIX_SRC}/build"
        RESULTS_DIR="''${HOME}/nix-test-results"
        TIMEOUT_MULT=10

        mkdir -p "$RESULTS_DIR"

        cd "$NIX_SRC"

        echo "=== Running Nix tests on s390x ==="
        echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Machine: $(uname -m) $(uname -r)"
        echo "jq: $(jq --version 2>/dev/null || echo 'not found')"
        echo "sandbox shell: $(file /usr/bin/bash-static 2>/dev/null || echo 'not found')"
        echo ""

        # Parse individual test counts from a meson test log.
        # Meson prints a summary line like: "Ok:  1932  Expected Fail:  0  Fail:  0  ..."
        parse_test_counts() {
            local logfile="$1"
            local ok skip fail
            ok=$(grep -oP 'Ok:\s+\K[0-9]+' "$logfile" | tail -n 1)
            skip=$(grep -oP 'Skipped:\s+\K[0-9]+' "$logfile" | tail -n 1)
            fail=$(grep -oP 'Fail:\s+\K[0-9]+' "$logfile" | tail -n 1)
            echo "''${ok:-0} ''${skip:-0} ''${fail:-0}"
        }

        # Unit tests (C++ GoogleTest)
        echo "--- Unit tests ---"
        total_unit_ok=0
        total_unit_fail=0
        for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
            echo ""
            echo "Running ''${suite}..."
            if meson test -C "$BUILD_DIR" "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" 2>&1 | tee "''${RESULTS_DIR}/''${suite}.log"; then
                echo "PASS: ''${suite}"
            else
                echo "FAIL: ''${suite} (see ''${RESULTS_DIR}/''${suite}.log)"
            fi
            read -r ok skip fail < <(parse_test_counts "''${RESULTS_DIR}/''${suite}.log")
            total_unit_ok=$((total_unit_ok + ok))
            total_unit_fail=$((total_unit_fail + fail))
        done

        # Functional tests — all suites
        echo ""
        echo "--- Functional tests ---"
        func_suites=(main flakes ca dyn-drv git git-hashing local-overlay-store plugins libstoreconsumer)
        total_func_ok=0
        total_func_skip=0
        total_func_fail=0

        for suite in "''${func_suites[@]}"; do
            echo ""
            echo "Running functional suite: ''${suite}..."
            if meson test -C "$BUILD_DIR" --suite "$suite" --verbose --timeout-multiplier "$TIMEOUT_MULT" --print-errorlogs 2>&1 | tee "''${RESULTS_DIR}/functional-''${suite}.log"; then
                echo "PASS: functional ''${suite}"
            else
                echo "SOME FAILURES in functional ''${suite} (see ''${RESULTS_DIR}/functional-''${suite}.log)"
            fi
            read -r ok skip fail < <(parse_test_counts "''${RESULTS_DIR}/functional-''${suite}.log")
            total_func_ok=$((total_func_ok + ok))
            total_func_skip=$((total_func_skip + skip))
            total_func_fail=$((total_func_fail + fail))
        done

        # Summary
        echo ""
        echo "=== Summary ==="
        echo "Unit tests:       ''${total_unit_ok} passed, ''${total_unit_fail} failed"
        echo "Functional tests: ''${total_func_ok} passed, ''${total_func_fail} failed, ''${total_func_skip} skipped"
        echo ""
        echo "Logs saved to ''${RESULTS_DIR}/"
        echo ""
        echo "Phase 17 complete: tests executed."
      '';
    };

    # --- 18: Verify test environment ---
    "18-verify-test-env" = mkZScript {
      name = "18-verify-test-env";
      needsEnv = true;
      description = "Verify the Nix build and test environment on the target machine";
      text = ''
        # Verify the Nix build and test environment on the target machine.
        # Run after building Nix (13-nix-build.sh) but before running tests.
        # This script probes every prerequisite the test suite needs and reports
        # what will pass, fail, or skip — before you spend 20 minutes finding out.

        NIX_SRC="''${HOME}/nix"
        BUILD_DIR="''${NIX_SRC}/build"

        PASS=0
        WARN=0
        FAIL=0
        INFO=0

        pass() { PASS=$((PASS + 1)); printf "  \033[32mPASS\033[0m  %s\n" "$*"; }
        warn() { WARN=$((WARN + 1)); printf "  \033[33mWARN\033[0m  %s\n" "$*"; }
        fail() { FAIL=$((FAIL + 1)); printf "  \033[31mFAIL\033[0m  %s\n" "$*"; }
        info() { INFO=$((INFO + 1)); printf "  \033[36mINFO\033[0m  %s\n" "$*"; }

        divider() { printf "\n=== %s ===\n" "$1"; }

        # ---------------------------------------------------------------------------
        divider "System"
        # ---------------------------------------------------------------------------

        info "Architecture: $(uname -m)"
        info "Kernel: $(uname -r)"
        os_name=$(grep -oP '^PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null) || os_name=$(uname -s)
        info "OS: $os_name"

        if [[ "$(uname -m)" == "s390x" ]]; then
            pass "Running on s390x"
        else
            info "Not s390x — that's fine, this script works on any arch"
        fi

        # ---------------------------------------------------------------------------
        divider "Nix Build"
        # ---------------------------------------------------------------------------

        if [[ -d "$BUILD_DIR" ]]; then
            pass "Build directory exists: $BUILD_DIR"
        else
            fail "Build directory not found: $BUILD_DIR"
            echo "       Run meson setup + meson compile first."
        fi

        nix_bin="$BUILD_DIR/src/nix/nix"
        if [[ -x "$nix_bin" ]]; then
            nix_version=$("$nix_bin" --version 2>/dev/null || echo "unknown")
            pass "Nix binary built: $nix_version"
        else
            fail "Nix binary not found at $nix_bin"
        fi

        installed_nix=$(command -v nix 2>/dev/null || true)
        if [[ -n "$installed_nix" ]]; then
            installed_version=$(nix --version 2>/dev/null || echo "unknown")
            info "Installed nix: $installed_nix ($installed_version)"
        else
            warn "No nix on PATH — some tests need an installed nix"
        fi

        # ---------------------------------------------------------------------------
        divider "Sandbox Shell"
        # ---------------------------------------------------------------------------

        # The sandbox shell is a static binary that Nix bind-mounts as /bin/sh
        # inside the build sandbox. Without it, sandboxed builds can't run.

        sandbox_shell=""
        config_hdr="$BUILD_DIR/src/libstore/store-config-private.hh"
        if [[ -f "$config_hdr" ]]; then
            sandbox_shell=$(grep '^#define SANDBOX_SHELL ' "$config_hdr" \
                | sed 's/.*"\(.*\)".*/\1/' 2>/dev/null || true)
        fi

        if [[ -n "$sandbox_shell" && "$sandbox_shell" != "__embedded_sandbox_shell__" ]]; then
            pass "Sandbox shell configured: $sandbox_shell"
            if [[ -x "$sandbox_shell" ]]; then
                pass "Sandbox shell binary exists and is executable"
            else
                fail "Sandbox shell binary not found: $sandbox_shell"
            fi
            if file "$sandbox_shell" 2>/dev/null | grep -q "statically linked"; then
                pass "Sandbox shell is statically linked"
            else
                warn "Sandbox shell is dynamically linked — may not work inside empty chroot"
            fi
            if "$sandbox_shell" -c 'echo ok' >/dev/null 2>&1; then
                pass "Sandbox shell executes successfully"
            else
                fail "Sandbox shell won't execute"
            fi
        else
            fail "No sandbox shell configured (SANDBOX_SHELL not set in build)"
            echo "       Sandboxed builds will fail. Install bash-static and reconfigure:"
            echo "       meson setup build --reconfigure -Dlibstore:sandbox-shell=/usr/bin/bash-static"
        fi

        # Check for common sandbox shell candidates
        for candidate in /usr/bin/bash-static /usr/bin/busybox; do
            if [[ -x "$candidate" ]]; then
                linkage=$(file "$candidate" | grep -o 'statically linked' || echo 'dynamic')
                info "Available static shell: $candidate ($linkage)"
            fi
        done

        # busybox warning
        if command -v busybox >/dev/null 2>&1; then
            warn "busybox is on PATH — meson will detect it for functional tests"
            echo "       This causes 19+ functional tests to run (instead of skip) and fail"
            echo "       because Ubuntu's busybox can't handle the test scripts."
            echo "       Consider: sudo apt-get remove busybox-static"
        fi

        # ---------------------------------------------------------------------------
        divider "Functional Test Variables"
        # ---------------------------------------------------------------------------

        subst_vars="$BUILD_DIR/src/nix-functional-tests/common/subst-vars.sh"
        if [[ -f "$subst_vars" ]]; then
            pass "Generated subst-vars.sh exists"

            # Source it to check variables (unset first to avoid leaking caller env)
            unset bash bindir system version shell busybox 2>/dev/null || true
            # shellcheck disable=SC1090
            source "$subst_vars"

            if [[ -n "''${bash:-}" ]]; then pass "\$bash = $bash"; else fail "\$bash is not set"; fi
            if [[ -n "''${bindir:-}" ]]; then pass "\$bindir = $bindir"; else fail "\$bindir is not set"; fi
            if [[ -n "''${system:-}" ]]; then pass "\$system = $system"; else fail "\$system is not set"; fi
            if [[ -n "''${version:-}" ]]; then pass "\$version = $version"; else fail "\$version is not set"; fi

            if [[ -n "''${shell:-}" ]]; then
                pass "\$shell = $shell"
            else
                fail "\$shell is not set — formatter.sh and nix-profile.sh will fail"
                echo "       Fix: add 'shell=@bash@' to tests/functional/common/subst-vars.sh.in"
            fi

            if [[ -z "''${busybox:-}" ]]; then
                pass "\$busybox is empty — busybox-dependent tests will skip (good)"
            else
                warn "\$busybox = $busybox — busybox-dependent tests will run"
            fi
        else
            fail "subst-vars.sh not generated — run meson setup first"
        fi

        # ---------------------------------------------------------------------------
        divider "User Namespaces (Sandbox Support)"
        # ---------------------------------------------------------------------------

        if [[ "$(uname)" == "Linux" ]]; then
            if [[ -L /proc/self/ns/user ]]; then
                pass "User namespace support detected (/proc/self/ns/user exists)"
            else
                warn "No /proc/self/ns/user — sandbox tests will skip"
            fi

            if unshare --user true 2>/dev/null; then
                pass "unshare --user works — sandboxed tests can run"
            else
                warn "unshare --user failed — sandboxed tests will skip"
            fi

            if [[ -f /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]]; then
                val=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
                if [[ "$val" == "0" ]]; then
                    pass "AppArmor unprivileged user namespaces: allowed"
                else
                    warn "AppArmor restricts unprivileged user namespaces — some tests will skip"
                fi
            fi
        fi

        # ---------------------------------------------------------------------------
        divider "Git"
        # ---------------------------------------------------------------------------

        if command -v git >/dev/null 2>&1; then
            git_version=$(git --version)
            pass "git installed: $git_version"

            # Check if file:// transport is restricted (CVE-2022-39253 backport)
            tmpdir=$(mktemp -d)

            git init -q "$tmpdir/a" 2>/dev/null
            git -C "$tmpdir/a" config user.email "test@test.com"
            git -C "$tmpdir/a" config user.name "Test"
            git -C "$tmpdir/a" commit --allow-empty -m init -q 2>/dev/null

            if git clone -q "file://$tmpdir/a" "$tmpdir/b" 2>/dev/null; then
                pass "git file:// transport works by default"
            else
                warn "git file:// transport is restricted (CVE-2022-39253 backport)"
                echo "       fetchGitSubmodules test may fail on recursive submodule clones"

                # Test if GIT_CONFIG_COUNT workaround helps
                if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
                   git clone -q "file://$tmpdir/a" "$tmpdir/c" 2>/dev/null; then
                    pass "GIT_CONFIG_COUNT workaround works for direct clones"
                else
                    fail "GIT_CONFIG_COUNT workaround does not work"
                fi

                # Test recursive submodule propagation
                git init -q "$tmpdir/d" 2>/dev/null
                git -C "$tmpdir/d" config user.email "test@test.com"
                git -C "$tmpdir/d" config user.name "Test"
                git -C "$tmpdir/d" commit --allow-empty -m init -q 2>/dev/null

                GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
                  git -C "$tmpdir/a" submodule add "$tmpdir/d" sub 2>/dev/null || true
                git -C "$tmpdir/a" commit -m sub -q 2>/dev/null || true

                if GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
                   git clone -q --recurse-submodules "file://$tmpdir/a" "$tmpdir/e" 2>/dev/null; then
                    pass "GIT_CONFIG_COUNT propagates to recursive submodule clones"
                else
                    warn "GIT_CONFIG_COUNT does NOT propagate to recursive submodule clones"
                    echo "       fetchGitSubmodules nested test will fail"
                    echo "       This is a git version issue ($git_version)"
                fi
            fi
            rm -rf "$tmpdir"
        else
            fail "git not installed — many tests will skip or fail"
        fi

        # ---------------------------------------------------------------------------
        divider "/nix/store"
        # ---------------------------------------------------------------------------

        if [[ -d /nix/store ]]; then
            count=$(find /nix/store -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)
            if [[ "$count" -gt 10 ]]; then
                pass "/nix/store exists with $count entries"
            elif [[ "$count" -gt 0 ]]; then
                warn "/nix/store exists but has only $count entries — nested-sandboxing may fail"
            else
                warn "/nix/store exists but is empty — nested-sandboxing will fail"
            fi
        else
            info "/nix/store does not exist — nested-sandboxing test will skip (good)"
        fi

        # ---------------------------------------------------------------------------
        divider "External Tools"
        # ---------------------------------------------------------------------------

        for tool in jq sqlite3 dot hg ssh-keygen; do
            if command -v "$tool" >/dev/null 2>&1; then
                ver=$("$tool" --version 2>/dev/null | head -1 || echo "")
                pass "$tool: found''${ver:+ ($ver)}"
            else
                info "$tool: not found (some tests may skip)"
            fi
        done

        # ---------------------------------------------------------------------------
        divider "Shared Libraries"
        # ---------------------------------------------------------------------------

        if [[ -x "$nix_bin" ]]; then
            missing=$(ldd "$nix_bin" 2>/dev/null | grep "not found" || true)
            if [[ -z "$missing" ]]; then
                pass "All shared libraries for nix binary resolved"
            else
                fail "Missing shared libraries:"
                echo "       ''${missing//$'\n'/$'\n'       }"
            fi
        fi

        # ---------------------------------------------------------------------------
        divider "Unit Test Binaries"
        # ---------------------------------------------------------------------------

        for suite in nix-util-tests nix-store-tests nix-expr-tests nix-fetchers-tests nix-flake-tests; do
            found=""
            for b in "$BUILD_DIR/src/$suite/$suite" "$BUILD_DIR/src/lib''${suite#nix-}/$suite"; do
                if [[ -x "$b" ]]; then found="$b"; break; fi
            done
            if [[ -n "$found" ]]; then
                missing=$(ldd "$found" 2>/dev/null | grep "not found" || true)
                if [[ -z "$missing" ]]; then
                    pass "$suite: binary OK"
                else
                    fail "$suite: missing libs"
                fi
            else
                warn "$suite: binary not found"
            fi
        done

        # ---------------------------------------------------------------------------
        divider "Known Failure Predictions"
        # ---------------------------------------------------------------------------

        echo ""
        echo "Based on the checks above, predicting functional test outcomes:"
        echo ""

        # formatter.sh / nix-profile.sh
        if [[ -n "''${shell:-}" ]]; then
            pass "formatter.sh — \$shell is defined"
            pass "nix-profile.sh — \$shell is defined"
        else
            fail "formatter.sh — will fail: \$shell unbound variable"
            fail "nix-profile.sh — will fail: \$shell unbound variable"
        fi

        # structured-attrs.sh
        if nix --extra-experimental-features "nix-command flakes" registry list 2>/dev/null | grep -q nixpkgs; then
            pass "structured-attrs.sh — nixpkgs in flake registry"
        else
            warn "structured-attrs.sh — will fail: 'nix develop' needs flake:nixpkgs (TODO_NixOS upstream)"
        fi

        # fetchGitSubmodules.sh — already checked above in Git section

        # nested-sandboxing.sh
        if [[ -d /nix/store ]]; then
            nix_bin_in_store=$(find /nix/store -name nix -type f -executable 2>/dev/null | head -1)
            if [[ -n "$nix_bin_in_store" ]]; then
                pass "nested-sandboxing.sh — nix binary found in /nix/store"
            else
                warn "nested-sandboxing.sh — will fail: needs nix deps in /nix/store"
            fi
        else
            pass "nested-sandboxing.sh — /nix/store absent, test will skip"
        fi

        # ---------------------------------------------------------------------------
        divider "Summary"
        # ---------------------------------------------------------------------------

        echo ""
        printf "  \033[32m%d PASS\033[0m  " "$PASS"
        printf "\033[33m%d WARN\033[0m  " "$WARN"
        printf "\033[31m%d FAIL\033[0m  " "$FAIL"
        printf "\033[36m%d INFO\033[0m\n" "$INFO"
        echo ""

        if [[ "$FAIL" -gt 0 ]]; then
            echo "There are $FAIL issues that will cause test failures."
            echo "Fix them before running the test suite."
            exit 1
        else
            echo "Environment looks good. Run tests with:"
            echo "  meson test -C build -t 10                    # all tests"
            echo "  meson test -C build --suite main -t 10       # functional tests only"
            exit 0
        fi
      '';
    };

  }; # end scriptDefs

  # Ordered list of build scripts (for deploy.nix)
  buildOrder = [
    "00-apt-deps" "01-meson-pip" "02-gcc14" "03-env"
    "04-boost" "05-nlohmann-json" "06-toml11" "07-sqlite"
    "08-boehm-gc" "09-curl" "10-libgit2" "11-libseccomp"
    "12-blake3" "13-nix-build" "14-nix-install"
  ];

  # Ordered list of test scripts (for deploy.nix)
  testOrder = [
    "15-test-deps" "16-nix-build-tests" "17-run-tests"
  ];

  allScriptNames = buildOrder ++ testOrder ++ [ "18-verify-test-env" ];

in {
  # Per-script shellcheck checks (replaces bulk shellcheck in checks.nix)
  checks = builtins.listToAttrs (map (name: {
    inherit name;
    value = scriptDefs.${name}.check;
  }) allScriptNames);

  # Deployable scripts for source-bundle.nix (name + derivation pairs)
  deployScripts = map (name: {
    inherit name;
    script = scriptDefs.${name}.script;
  }) allScriptNames;

  # Script ordering for deploy.nix
  inherit buildOrder testOrder;

  # Individual script access
  scripts = builtins.mapAttrs (_: v: v.script) scriptDefs;
}
