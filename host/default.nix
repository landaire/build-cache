{ modulesPath, ... }:
let
  # The SSH keys of ~/dev/config's keys.nix `users` and `admins`.
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB6CmOIY8QOpHzEN3otjDVxtabXC6evXnSBtdVHY9e95 landerbrandt@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIfIfD4SY/F2kQLfLhc6M8iCK0zz8UOHo0Jj8UJNoDa9 lander@conficker.io"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICzPiahzSGQFXYWbaDmEtf/lRBybmCcfFLNaBmw6F/kZ landerbrandt@gmail.com"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOEJRFVk6T+YK1wYt77rTGZNc+5GSlSHuUg2cdyNgznC hello@landaire.net"
  ];
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk.nix
    ./network.nix
    ./nativelink.nix
  ];

  networking.hostName = "buck-cache";
  time.timeZone = "UTC";

  # Hetzner boots x86 servers through BIOS. The EFI install covers a switch to
  # UEFI without a reinstall.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  # Joining the tailnet is a one-time `tailscale up --advertise-tags=tag:buck-cache`.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "root" ];
  };
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 14d";
  };

  services.fstrim.enable = true;
  zramSwap.enable = true;

  system.stateVersion = "26.05";
}
