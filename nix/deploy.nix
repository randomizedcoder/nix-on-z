# Deployment apps as writeShellApplication (gets shellcheck for free).
#
# sync                  — rsync patched source bundle to z
# build-remote          — SSH to z and run build scripts
# test-remote           — SSH to z and run test suite
# verify-remote         — SSH to z and run environment verification
# fix-permissions       — SSH to z and fix source tree permissions after meson install
# build-clickhouse      — build ClickHouse natively on z from synced nixpkgs
# sync-clickhouse-tests — sparse-clone ClickHouse test suite to z
# test-clickhouse       — run ClickHouse functional tests on z
{ pkgs, self, zScripts }:

let
  system = "x86_64-linux";
  bundle = self.packages.${system}.source-bundle;

  # Generate the 'for s in ...; do bash "$s"; done' command from script ordering
  mkRunCmd = order:
    let
      scripts = map (n: "${n}.sh") order;
    in
      "for s in ${builtins.concatStringsSep " " scripts}; do echo \"=== $s ===\"; bash \"$s\" || exit 1; done";

  mkApp = drv: {
    type = "app";
    program = "${drv}/bin/${drv.name}";
  };
in
{
  sync = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-sync";
    runtimeInputs = [ pkgs.rsync pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Syncing patched nix source to $Z_HOST..."

      # Ensure target directories exist and are writable.
      # Nix store paths are read-only, so rsync copies inherit that — we must
      # chmod after sync or subsequent syncs/builds fail with permission denied.
      ssh "$Z_HOST" 'mkdir -p ~/nix ~/rapidcheck ~/nix-on-z/patches && chmod -R u+w ~/nix ~/rapidcheck ~/nix-on-z 2>/dev/null || true'

      rsync -avz --delete \
        --exclude='/build/' --exclude='/builddir/' \
        "${bundle}/nix-source/" "$Z_HOST:nix/"
      rsync -avz --delete \
        --exclude='/build/' \
        "${bundle}/rapidcheck-source/" "$Z_HOST:rapidcheck/"
      rsync -avz "${bundle}/scripts/" "$Z_HOST:nix-on-z/"
      rsync -avz "${bundle}/patches/" "$Z_HOST:nix-on-z/patches/"

      # Make synced files writable so builds can modify the source tree
      ssh "$Z_HOST" 'chmod -R u+w ~/nix ~/rapidcheck ~/nix-on-z'

      echo "Sync complete. ssh $Z_HOST and run scripts in ~/nix-on-z/"
    '';
  });

  build-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-build-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running build on $Z_HOST..."
      # Use sudo --preserve-env=HOME so scripts resolve ~/nix correctly.
      # Without this, sudo sets HOME=/root and scripts can't find the source.
      ssh "$Z_HOST" 'cd ~/nix-on-z && for s in ${builtins.concatStringsSep " " (map (n: "${n}.sh") zScripts.buildOrder)}; do echo "=== $s ==="; sudo --preserve-env=HOME bash "$s" || exit 1; done'
      # Fix /nix ownership after sudo build — single-user nix needs the
      # build user to own /nix, but sudo leaves it owned by root.
      ssh "$Z_HOST" 'sudo chown -R $(whoami):$(whoami) /nix'
      echo "Build complete."
    '';
  });

  test-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-test-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running tests on $Z_HOST..."
      ssh "$Z_HOST" 'cd ~/nix-on-z && for s in ${builtins.concatStringsSep " " (map (n: "${n}.sh") zScripts.testOrder)}; do echo "=== $s ==="; sudo --preserve-env=HOME bash "$s" || exit 1; done'
      echo "Tests complete."
    '';
  });

  verify-remote = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-verify-remote";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running environment verification on $Z_HOST..."
      ssh "$Z_HOST" 'cd ~/nix-on-z && bash 18-verify-test-env.sh'
    '';
  });

  check-arch = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-check-arch";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Checking s390x hardware on $Z_HOST..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'bash -s' <<'REMOTE_SCRIPT'

      CURRENT_ARCH="''${1:-z13}"

      if [[ ! -f /proc/cpuinfo ]]; then
        echo "ERROR: /proc/cpuinfo not found. Are you running on s390x?"
        exit 1
      fi

      MACHINE_TYPE=$(grep -m1 "^processor.*machine" /proc/cpuinfo | awk "{print \$NF}")
      FEATURES=$(grep "^features" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
      CPUS=$(grep "^# processors" /proc/cpuinfo | awk "{print \$NF}")

      echo "=== IBM Z Hardware Detection ==="
      echo "Machine type:    $MACHINE_TYPE"
      echo "Processors:      ''${CPUS:-unknown}"
      echo "CPU features:    $FEATURES"
      echo ""

      # Machine type -> gcc -march mapping
      # See: https://gcc.gnu.org/onlinedocs/gcc/S_002f390-and-zSeries-Options.html
      case "$MACHINE_TYPE" in
        2964|2965) DETECTED_ARCH="z13";   YEAR="2015"; HW_FEATURES="VXE (vector extensions)" ;;
        3906|3907) DETECTED_ARCH="z14";   YEAR="2017"; HW_FEATURES="VXE2, misc-insn-ext-2" ;;
        8561|8562) DETECTED_ARCH="z15";   YEAR="2019"; HW_FEATURES="VXE3, DFLTCC (hardware deflate), sort" ;;
        3931|3932) DETECTED_ARCH="z16";   YEAR="2022"; HW_FEATURES="NNPA (AI accelerator), bear-enh-1" ;;
        9175)      DETECTED_ARCH="arch15"; YEAR="2025"; HW_FEATURES="z17 features (requires GCC 15+)" ;;
        *)         echo "WARNING: Unknown machine type $MACHINE_TYPE"; exit 1 ;;
      esac

      # Arch level ordering for comparison
      arch_level() {
        case "$1" in
          z13) echo 5 ;; z14) echo 6 ;; z15) echo 7 ;;
          z16) echo 8 ;; arch15) echo 9 ;; *) echo 0 ;;
        esac
      }

      echo "Detected:        $DETECTED_ARCH ($YEAR) — $HW_FEATURES"
      echo "Configured:      gcc.arch = \"$CURRENT_ARCH\""
      echo ""

      DETECTED_LEVEL=$(arch_level "$DETECTED_ARCH")
      CURRENT_LEVEL=$(arch_level "$CURRENT_ARCH")

      if [[ "$DETECTED_LEVEL" -gt "$CURRENT_LEVEL" ]]; then
        echo ">>> RECOMMENDATION: Your hardware supports gcc.arch = \"$DETECTED_ARCH\""
        echo "    which is higher than the currently configured \"$CURRENT_ARCH\"."
        echo ""
        echo "    To optimize, edit lib/systems/examples.nix:"
        echo "      gcc.arch = \"$DETECTED_ARCH\";"
        echo ""
        echo "    This enables: $HW_FEATURES"
        if [[ "$DETECTED_LEVEL" -ge 7 ]] && [[ "$CURRENT_LEVEL" -lt 7 ]]; then
          echo ""
          echo "    NOTE: z15+ enables DFLTCC (hardware deflate) for zlib/gzip."
          echo "          10-50x faster compression with -march=z15."
        fi
      elif [[ "$DETECTED_LEVEL" -eq "$CURRENT_LEVEL" ]]; then
        echo "OK: gcc.arch = \"$CURRENT_ARCH\" matches your hardware."
      else
        echo "NOTE: gcc.arch = \"$CURRENT_ARCH\" targets newer hardware than detected."
        echo "      Binaries may not run correctly on this machine."
      fi
REMOTE_SCRIPT
    '';
  });

  tune-ubuntu = mkApp (import ./z-tuning { inherit pkgs; });

  fix-permissions = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-fix-permissions";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      REMOTE_USER="''${REMOTE_USER:-$(ssh "$Z_HOST" whoami)}"
      echo "Fixing source tree permissions on $Z_HOST..."
      # meson install (via sudo) can leave files owned by root and read-only.
      # This restores user ownership and write permissions so subsequent
      # builds and tests can modify the source tree.
      ssh "$Z_HOST" "sudo chown -R $REMOTE_USER:$REMOTE_USER ~/nix && chmod -R u+w ~/nix"
      echo "Permissions fixed."
    '';
  });

  # Sync our patched nixpkgs to z for native s390x builds (e.g. ClickHouse).
  # This is separate from the nix source sync — nixpkgs is ~2GB and lives in
  # ~/nixpkgs on z, not ~/nix.
  sync-nixpkgs = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-sync-nixpkgs";
    runtimeInputs = [ pkgs.rsync pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      NIXPKGS_SRC="''${NIXPKGS_SRC:-$HOME/Downloads/z/nixpkgs}"

      if [[ ! -d "$NIXPKGS_SRC" ]]; then
        echo "ERROR: nixpkgs source not found at $NIXPKGS_SRC"
        echo "Set NIXPKGS_SRC to your patched nixpkgs checkout"
        exit 1
      fi

      echo "Syncing nixpkgs to $Z_HOST..."
      # Do NOT exclude .git — nix needs it for source tracking and version detection
      rsync -avz --delete \
        --exclude='/result' --exclude='/result-*' \
        "$NIXPKGS_SRC/" "$Z_HOST:nixpkgs/"
      echo "Sync complete."
      echo ""
      echo "To build ClickHouse on $Z_HOST:"
      echo "  ssh $Z_HOST"
      echo "  cd ~/nixpkgs && nix-build -A clickhouse --cores \$(nproc) -j 2"
    '';
  });

  # Configure nix on z for s390x builds (system-features, store init).
  # Run this after nix is installed but before any nix-build.
  setup-nix = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-setup-nix";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Configuring nix on $Z_HOST for s390x builds..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'sudo bash -s' <<'REMOTE_SCRIPT'
      set -euo pipefail

      # Create nix config directory
      mkdir -p /etc/nix

      # Set system-features to match gcc.arch=z15 in platforms.nix.
      # Without this, all derivations fail with "missing system features: gccarch-z15"
      cat > /etc/nix/nix.conf <<'NIXCONF'
      system-features = benchmark big-parallel gccarch-z15 nixos-test uid-range
      sandbox = false
      max-jobs = auto
      cores = 0
NIXCONF

      # Initialize single-user nix store if not present
      REMOTE_USER=$(logname 2>/dev/null || echo linux1)
      STORE_ROOT="/home/$REMOTE_USER/.local/share/nix/root"
      if [[ ! -d "$STORE_ROOT/nix/store" ]]; then
        echo "  Initializing nix store at $STORE_ROOT..."
        mkdir -p "$STORE_ROOT/nix/store"
        mkdir -p "$STORE_ROOT/nix/var/nix/db"
        chown -R "$REMOTE_USER:$REMOTE_USER" "$STORE_ROOT"
      else
        echo "  Nix store already exists at $STORE_ROOT"
      fi

      # Fix /nix ownership — build-remote installs nix as root via sudo,
      # leaving /nix owned by root. Single-user nix needs it owned by the
      # build user so nix-build can write to the store.
      if [[ -d /nix ]]; then
        echo "  Fixing /nix ownership to $REMOTE_USER..."
        chown -R "$REMOTE_USER:$REMOTE_USER" /nix
      fi

      echo "  nix.conf written to /etc/nix/nix.conf"
      echo "  system-features: benchmark big-parallel gccarch-z15 nixos-test uid-range"
      echo "Done."
REMOTE_SCRIPT
    '';
  });

  # Verify nix is working before attempting nix-build.
  # Checks: binary exists, version, store is writable, system-features match,
  # and a trivial derivation builds successfully.
  verify-nix = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-verify-nix";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Verifying nix on $Z_HOST..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'bash -s' <<'REMOTE_SCRIPT'
      set -euo pipefail
      PASS=0
      FAIL=0

      check() {
        if eval "$2" > /dev/null 2>&1; then
          echo "  PASS: $1"
          PASS=$((PASS + 1))
        else
          echo "  FAIL: $1"
          FAIL=$((FAIL + 1))
        fi
      }

      echo "=== Nix Installation ==="
      check "nix binary exists" "command -v nix"
      check "nix --version runs" "nix --version"
      echo "  $(nix --version 2>/dev/null || echo 'not installed')"

      echo ""
      echo "=== Store Permissions ==="
      check "/nix/store exists" "test -d /nix/store"
      check "/nix/store is writable" "touch /nix/store/.write-test && rm /nix/store/.write-test"
      STORE_OWNER=$(stat -c '%U' /nix/store 2>/dev/null || echo 'unknown')
      echo "  /nix/store owner: $STORE_OWNER"

      echo ""
      echo "=== Configuration ==="
      check "nix.conf exists" "test -f /etc/nix/nix.conf"
      if [ -f /etc/nix/nix.conf ]; then
        FEATURES=$(grep 'system-features' /etc/nix/nix.conf 2>/dev/null || echo 'not set')
        echo "  $FEATURES"
        check "gccarch-z15 in system-features" "grep -q gccarch-z15 /etc/nix/nix.conf"
      fi

      echo ""
      echo "=== Trivial Build Test ==="
      check "nix-build trivial derivation" "nix-build -E 'derivation { name = \"test\"; system = \"s390x-linux\"; builder = /bin/sh; args = [\"-c\" \"echo ok > \\\$out\"]; }' --no-out-link"

      echo ""
      echo "=== Result: $PASS passed, $FAIL failed ==="
      if [ "$FAIL" -gt 0 ]; then
        echo "Fix issues before running nix-build."
        exit 1
      else
        echo "Nix is ready for building."
      fi
REMOTE_SCRIPT
    '';
  });

  # Build ClickHouse natively on z from the synced nixpkgs.
  build-clickhouse = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-build-clickhouse";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      CORES="''${CORES:-4}"
      JOBS="''${JOBS:-2}"
      echo "Building ClickHouse on $Z_HOST (--cores $CORES -j $JOBS)..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" "cd ~/nixpkgs && nix-build -A clickhouse --cores $CORES -j $JOBS 2>&1 | tee ~/clickhouse-build.log"
      echo ""
      echo "Verifying build..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'file ~/nixpkgs/result/bin/clickhouse && ~/nixpkgs/result/bin/clickhouse local --version && ~/nixpkgs/result/bin/clickhouse local --query "SELECT 1"'
      echo "ClickHouse build complete."
    '';
  });

  # Clone ClickHouse test suite to z (sparse checkout — tests/ directory only).
  sync-clickhouse-tests = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-sync-clickhouse-tests";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      CH_VERSION="v26.2.4.23-stable"
      echo "Syncing ClickHouse test suite ($CH_VERSION) to $Z_HOST..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" "bash -s -- $CH_VERSION" <<'REMOTE_SCRIPT'
      set -euo pipefail
      CH_VERSION="$1"
      TEST_DIR=~/clickhouse-tests
      if [[ -d "$TEST_DIR/tests" ]]; then
        echo "  Tests already present at $TEST_DIR/tests"
        echo "  To re-clone, remove $TEST_DIR first"
        ls "$TEST_DIR/tests/" | head -10
      else
        echo "  Sparse-cloning ClickHouse repo (tests/ only)..."
        rm -rf "$TEST_DIR"
        git clone --depth 1 --branch "$CH_VERSION" --filter=blob:none --sparse \
          https://github.com/ClickHouse/ClickHouse.git "$TEST_DIR"
        cd "$TEST_DIR"
        git sparse-checkout set tests/
        echo "  Clone complete."
        ls tests/
      fi
REMOTE_SCRIPT
    '';
  });

  # Build minio (S3-compatible object store) on z for ClickHouse S3 tests.
  build-minio = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-build-minio";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      CORES="''${CORES:-4}"
      JOBS="''${JOBS:-2}"
      echo "Building minio on $Z_HOST (--cores $CORES -j $JOBS)..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" "cd ~/nixpkgs && nix-build -A minio -o ~/minio-result --cores $CORES -j $JOBS 2>&1 | tee ~/minio-build.log"
      echo ""
      echo "Verifying build..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'file ~/minio-result/bin/minio && ~/minio-result/bin/minio --version'
      echo "Minio build complete. Symlink at ~/minio-result"
    '';
  });

  # Run ClickHouse test suite on z.
  # Sets up a temporary server, runs clickhouse-test, reports results.
  test-clickhouse = mkApp (pkgs.writeShellApplication {
    name = "nix-on-z-test-clickhouse";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      Z_HOST="''${Z_HOST:-z}"
      echo "Running ClickHouse tests on $Z_HOST..."
      # shellcheck disable=SC2029
      ssh "$Z_HOST" 'bash -s' <<'REMOTE_SCRIPT'
      set -euo pipefail

      CH=~/nixpkgs/result/bin/clickhouse
      TEST_DIR=~/clickhouse-tests
      DATA_DIR=/tmp/ch-test-server

      if [[ ! -x "$CH" ]]; then
        echo "ERROR: ClickHouse binary not found at $CH"
        echo "Run 'nix run .#build-clickhouse' first."
        exit 1
      fi

      if [[ ! -d "$TEST_DIR/tests" ]]; then
        echo "ERROR: Test suite not found at $TEST_DIR/tests"
        echo "Run 'nix run .#sync-clickhouse-tests' first."
        exit 1
      fi

      # Clean up any previous test server and minio
      pkill -f "clickhouse server.*ch-test-server" 2>/dev/null || true
      pkill -f "minio server" 2>/dev/null || true
      sleep 1
      rm -rf "$DATA_DIR"
      mkdir -p "$DATA_DIR"/{data,tmp,user_files,format_schemas,log,access,minio-data}

      # Ensure jq is available (needed by some tests)
      if ! command -v jq &>/dev/null; then
        echo "Installing jq..."
        sudo apt-get install -y jq
      fi

      # Write server config with query_log, clusters, and RBAC support
      cat > "$DATA_DIR/config.xml" <<'XMLEOF'
<?xml version="1.0"?>
<clickhouse>
    <path>/tmp/ch-test-server/data/</path>
    <tmp_path>/tmp/ch-test-server/tmp/</tmp_path>
    <user_files_path>/tmp/ch-test-server/user_files/</user_files_path>
    <format_schema_path>/tmp/ch-test-server/format_schemas/</format_schema_path>
    <access_control_path>/tmp/ch-test-server/access/</access_control_path>
    <logger>
        <log>/tmp/ch-test-server/log/clickhouse-server.log</log>
        <errorlog>/tmp/ch-test-server/log/clickhouse-server.err.log</errorlog>
        <level>information</level>
    </logger>
    <tcp_port>9000</tcp_port>
    <http_port>8123</http_port>
    <interserver_http_port>9009</interserver_http_port>
    <listen_host>127.0.0.1</listen_host>
    <listen_host>127.0.0.2</listen_host>
    <mark_cache_size>5368709120</mark_cache_size>
    <max_concurrent_queries>500</max_concurrent_queries>

    <query_log>
        <database>system</database>
        <table>query_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </query_log>
    <query_thread_log>
        <database>system</database>
        <table>query_thread_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </query_thread_log>
    <part_log>
        <database>system</database>
        <table>part_log</table>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </part_log>
    <metric_log>
        <database>system</database>
        <table>metric_log</table>
        <collect_interval_milliseconds>1000</collect_interval_milliseconds>
        <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    </metric_log>

    <remote_servers>
        <parallel_replicas>
            <shard>
                <internal_replication>false</internal_replication>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </parallel_replicas>
        <test_shard_localhost>
            <shard>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_shard_localhost>
        <test_cluster_one_shard_three_replicas_localhost>
            <shard>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_cluster_one_shard_three_replicas_localhost>
        <test_cluster_two_shards_localhost>
            <shard>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
            <shard>
                <replica>
                    <host>127.0.0.1</host>
                    <port>9000</port>
                </replica>
            </shard>
        </test_cluster_two_shards_localhost>
    </remote_servers>

    <user_directories>
        <users_xml>
            <path>/tmp/ch-test-server/users.xml</path>
        </users_xml>
        <local_directory>
            <path>/tmp/ch-test-server/access/</path>
        </local_directory>
    </user_directories>

    <storage_configuration>
        <disks>
            <s3_disk>
                <type>s3</type>
                <endpoint>http://127.0.0.1:9001/clickhouse-test/s3_disk/</endpoint>
                <access_key_id>clickhouse</access_key_id>
                <secret_access_key>clickhouse</secret_access_key>
            </s3_disk>
            <s3_plain_rewritable>
                <type>s3_plain_rewritable</type>
                <endpoint>http://127.0.0.1:9001/clickhouse-test/s3_plain/</endpoint>
                <access_key_id>clickhouse</access_key_id>
                <secret_access_key>clickhouse</secret_access_key>
            </s3_plain_rewritable>
        </disks>
    </storage_configuration>

    <named_collections>
        <s3_conn>
            <url>http://127.0.0.1:9001/clickhouse-test/</url>
            <access_key_id>clickhouse</access_key_id>
            <secret_access_key>clickhouse</secret_access_key>
        </s3_conn>
    </named_collections>

    <backups>
        <allowed_disk>s3_disk</allowed_disk>
        <allowed_disk>s3_plain_rewritable</allowed_disk>
    </backups>
</clickhouse>
XMLEOF

      cat > "$DATA_DIR/users.xml" <<'XMLEOF'
<?xml version="1.0"?>
<clickhouse>
    <profiles>
        <default/>
    </profiles>
    <users>
        <default>
            <password></password>
            <networks>
                <ip>::/0</ip>
            </networks>
            <profile>default</profile>
            <quota>default</quota>
            <access_management>1</access_management>
        </default>
    </users>
    <quotas>
        <default/>
    </quotas>
</clickhouse>
XMLEOF

      # Start minio (S3-compatible storage) if available
      MINIO_BIN=""
      if [[ -x ~/minio-result/bin/minio ]]; then
        MINIO_BIN=~/minio-result/bin/minio
      fi
      MINIO_PID=""
      if [[ -n "$MINIO_BIN" && -x "$MINIO_BIN" ]]; then
        echo "Starting minio S3 server..."
        export MINIO_ROOT_USER=clickhouse
        export MINIO_ROOT_PASSWORD=clickhouse
        "$MINIO_BIN" server "$DATA_DIR/minio-data" \
          --address 127.0.0.1:9001 \
          --console-address 127.0.0.1:9002 \
          > "$DATA_DIR/log/minio.log" 2>&1 &
        MINIO_PID=$!
        sleep 2
        if kill -0 "$MINIO_PID" 2>/dev/null; then
          echo "Minio running (PID $MINIO_PID) on http://127.0.0.1:9001"
          # Create the test bucket
          if command -v mc &>/dev/null; then
            mc alias set local http://127.0.0.1:9001 clickhouse clickhouse 2>/dev/null || true
            mc mb local/clickhouse-test 2>/dev/null || true
          else
            # Use curl to create bucket via S3 API
            curl -s -X PUT http://127.0.0.1:9001/clickhouse-test \
              -u clickhouse:clickhouse 2>/dev/null || true
          fi
        else
          echo "WARNING: Minio failed to start, S3 tests will be skipped"
          MINIO_PID=""
        fi
      else
        echo "Minio not built — S3 tests will be skipped. Run 'nix run .#build-minio' first."
      fi

      echo "Starting ClickHouse test server..."
      export MALLOC_CONF="background_thread:true,prof:true"
      "$CH" server --config-file "$DATA_DIR/config.xml" &
      SERVER_PID=$!
      sleep 5

      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "ERROR: Server failed to start. Log:"
        tail -20 "$DATA_DIR/log/clickhouse-server.log"
        exit 1
      fi

      echo "Server running (PID $SERVER_PID). Running tests..."
      echo ""

      # Run the stateless functional tests (the main test suite)
      cd "$TEST_DIR"
      RESULT=0
      python3 tests/clickhouse-test \
          --binary "$CH" \
          --queries tests/queries \
          --tmp "$DATA_DIR/tmp" \
          -j 2 \
          2>&1 | tee ~/clickhouse-test-results.log || RESULT=$?

      echo ""
      echo "=== Test Results ==="
      tail -20 ~/clickhouse-test-results.log
      echo ""

      # Cleanup
      echo "Stopping test server..."
      kill "$SERVER_PID" 2>/dev/null || true
      wait "$SERVER_PID" 2>/dev/null || true
      if [[ -n "$MINIO_PID" ]]; then
        echo "Stopping minio..."
        kill "$MINIO_PID" 2>/dev/null || true
        wait "$MINIO_PID" 2>/dev/null || true
      fi
      echo "Done. Full results in ~/clickhouse-test-results.log"
      exit $RESULT
REMOTE_SCRIPT
    '';
  });
}
