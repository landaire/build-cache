# Hetzner Cloud hands out IPv4 over DHCP but not the IPv6 address: the server
# owns a routed /64 and takes ::1 from it, with the gateway at fe80::1.
{
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.network.networks."10-uplink" = {
    matchConfig.Type = "ether";
    networkConfig.DHCP = "ipv4";
    address = [ "2a01:4f8:c016:e85::1/64" ];
    routes = [ { Gateway = "fe80::1"; } ];
  };
}
