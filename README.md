# build-cache

- A remote action cache for [Buck2](https://buck2.build) builds, shared by CI and your own machines.
- It runs [NativeLink](https://github.com/TraceMachina/nativelink) on a small Hetzner server named `buck-cache`.
- It is reachable only over the tailnet. CI jobs join it for the length of the job.
- The server is a NixOS configuration in this repository.

## Using the cache in a project's CI

The project's Buck2 platform has to turn the action cache on when `[buck2_re_client]` names an engine address. wows-toolkit's `platforms/defs.bzl` is an example.

Add a step to each building job, after the step that writes `.buckconfig.local`, and grant that job `id-token: write`:

```yaml
jobs:
  build:
    permissions:
      contents: read
      id-token: write
    steps:
      # ...
      - uses: landaire/build-cache/.github/actions/buck-cache@<commit>
        with:
          client-id: ${{ vars.TS_CLIENT_ID }}
          audience: ${{ vars.TS_AUDIENCE }}
```

The job joins the tailnet as an ephemeral `tag:ci` device and leaves when the job ends. GitHub signs the job's identity, so the repository stores no secret. Any device that joins can write to the cache, so only pushes and manual runs join. Pull requests, including those from forks, build without the cache.

Each repository needs its own [federated identity](https://tailscale.com/docs/features/workload-identity-federation#set-up-a-federated-identity) in the Tailscale admin console:

1. Create one for GitHub, with its subject limited to the repository's branches, for example `repo:landaire/wows-toolkit:ref:refs/heads/*`. A pull request's token carries a different subject, so it cannot join even if a workflow tries.
2. Select the **Auth Keys > Write** scope and the `tag:ci` tag.
3. Store its client ID and audience as the repository variables `TS_CLIENT_ID` and `TS_AUDIENCE`. Neither value is secret.

## Using the cache from your machines

Join the tailnet, then put this in a file under `~/.buckconfig.d/`:

```ini
[buck2_re_client]
engine_address = grpc://buck-cache.tail8a811.ts.net:50051
action_cache_address = grpc://buck-cache.tail8a811.ts.net:50051
cas_address = grpc://buck-cache.tail8a811.ts.net:50051
tls = false

[buck2]
default_allow_cache_upload = true
```

A cache entry is shared only when two machines run the identical action. The platform, the toolchain store paths and every Buck2 setting that reaches a command line have to match.

Machines on the home network can keep using a cache on the local network instead. Buck2 talks to one cache at a time.

## Tailscale policy

CI devices must reach the cache and nothing else. The policy needs these entries next to your existing ones:

```jsonc
"tagOwners": {
  "tag:buck-cache": ["autogroup:admin"],
  "tag:ci":         ["autogroup:admin"],
},
"grants": [
  // Your own devices keep reaching everything, including the cache.
  {"src": ["autogroup:member"], "dst": ["*"], "ip": ["*"]},
  // CI reaches only the cache port.
  {"src": ["tag:ci"], "dst": ["tag:buck-cache"], "ip": ["tcp:50051"]},
],
```

Remove any rule whose source is `*`. It would let CI devices reach your other machines.

## The server

`buck-cache` is a Hetzner CX23 in Falkenstein with a 100 GB volume for the cache. The Hetzner firewall allows SSH from one address, Tailscale's UDP port and ICMP. Nothing else is open to the internet.

Enter the tools with `nix develop`.

### Deploying a change

The server is too small to build NativeLink, so build here and copy the result:

```bash
nixos-rebuild switch --flake .#buck-cache --target-host root@buck-cache.tail8a811.ts.net
```

### Installing from scratch

The Hetzner resources are named `buck-cache` (server and firewall), `buck-cache-store` (volume), and `buck-cache-ipv4` and `buck-cache-ipv6` (addresses kept across reinstalls). If the volume is recreated, update its ID in `host/nativelink.nix`. If the IPv6 network changes, update `host/network.nix`. A new server's boot disk has a new serial, so update its ID in `host/disk.nix` from `ls -l /dev/disk/by-id/` on the server. Do not use `/dev/sda`: the volume can take that name.

1. Create the server from any Debian image with the addresses, volume, firewall and your SSH key:

   ```bash
   hcloud server create --name buck-cache --type cx23 --location fsn1 --image debian-13 \
     --primary-ipv4 buck-cache-ipv4 --primary-ipv6 buck-cache-ipv6 \
     --volume buck-cache-store --firewall buck-cache --ssh-key lander-ed25519
   ```

2. Install NixOS over it:

   ```bash
   nixos-anywhere --flake .#buck-cache root@<IPv4 address>
   ```

3. Join the tailnet. The command prints a login link:

   ```bash
   ssh root@<IPv4 address> tailscale up --advertise-tags=tag:buck-cache
   ```
