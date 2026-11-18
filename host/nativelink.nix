# NativeLink as a cache only: a content-addressed store and an action cache,
# with no scheduler or worker. Buck2 runs every action itself and reads and
# writes results here. The port is reachable only over the tailnet.
{ pkgs, nativelink, ... }:
let
  stateDir = "/var/lib/nativelink";
  port = 50051;
  # The Hetzner volume, formatted ext4 when it was created.
  volume = "/dev/disk/by-id/scsi-0HC_Volume_107514109";

  gib = n: n * 1024 * 1024 * 1024;

  # On reaching max_bytes, evict down to max_bytes - evict_bytes rather than to
  # the limit exactly, which would evict on every write once the store is full.
  filesystem = name: bytes: {
    content_path = "${stateDir}/${name}/content";
    temp_path = "${stateDir}/${name}/tmp";
    eviction_policy = {
      max_bytes = bytes;
      evict_bytes = bytes / 10;
    };
  };

  settings = {
    stores = [
      # Sized to leave the 100 GB volume room for the action cache, temporary
      # files and the filesystem. Every upload is hashed and sized before it is
      # stored, so a client cannot place bytes under a digest they do not have.
      # Build outputs compress about 2.3x with LZ4, and the limit counts the
      # compressed bytes on disk. Changing this layout means clearing the CAS.
      {
        name = "cas";
        verify = {
          backend.compression = {
            compression_algorithm.lz4 = { };
            backend.filesystem = filesystem "cas" (gib 85);
          };
          verify_size = true;
          verify_hash = true;
        };
      }
      # The action cache only returns a result whose outputs are all still in
      # the CAS. Without the check, a CAS eviction leaves entries that point at
      # missing blobs, and Buck2 fails to download them instead of running the
      # action.
      {
        name = "ac";
        completeness_checking = {
          backend.filesystem = filesystem "ac" (gib 2);
          cas_store.ref_store.name = "cas";
        };
      }
    ];

    servers = [
      {
        name = "client";
        listener.http = {
          socket_address = "0.0.0.0:${toString port}";
          # Clients are about 100 ms away. A fixed window caps each upload
          # stream at window / RTT, so let it grow with the link.
          advanced_http.experimental_http2_adaptive_window = true;
        };
        services = {
          cas = [ { cas_store = "cas"; } ];
          ac = [ { ac_store = "ac"; } ];
          bytestream = [ { cas_store = "cas"; } ];
          capabilities = [ { } ];
          health = { };
        };
      }
    ];

    global.max_open_files = 24576;
  };

  # JSON5 is a superset of JSON, so the generated file loads as-is.
  configFile = pkgs.writeText "nativelink.json" (builtins.toJSON settings);
in
{
  fileSystems.${stateDir} = {
    device = volume;
    fsType = "ext4";
    options = [
      "discard"
      "nofail"
    ];
  };

  # Fixed IDs, because the volume keeps its files' numeric owners across a
  # reinstall of the server.
  users.users.nativelink = {
    isSystemUser = true;
    uid = 2050;
    group = "nativelink";
  };
  users.groups.nativelink.gid = 2050;

  systemd.services.nativelink = {
    description = "NativeLink action cache";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = stateDir;

    serviceConfig = {
      ExecStart = "${nativelink.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/nativelink ${configFile}";
      # The volume's root belongs to root, and tmpfiles can run before the
      # volume is mounted, so the service takes ownership once it is.
      ExecStartPre = "+${pkgs.coreutils}/bin/chown nativelink:nativelink ${stateDir}";
      Restart = "on-failure";
      RestartSec = 5;

      User = "nativelink";
      Group = "nativelink";
      WorkingDirectory = stateDir;
      LimitNOFILE = 65536;

      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ stateDir ];
    };
  };

  # Only tailnet devices reach the cache. The Hetzner firewall drops the port
  # from the internet as well.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
