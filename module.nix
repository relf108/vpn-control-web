{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.homelab-vpn-web;
in
{
  options.services.homelab-vpn-web = {
    enable = lib.mkEnableOption "private Flutter VPN dashboard behind Caddy";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./default.nix { inherit pkgs; };
      description = "Flutter static-site package.";
    };
    hostAddress = lib.mkOption {
      type = lib.types.str;
      default = "192.168.0.100";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8443;
    };
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 1337;
    };
    allowedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "192.168.0.0/24"
        "10.77.0.0/24"
      ];
    };
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "enp2s0"
        "wg-home"
      ];
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.allowedNetworks != [ ] && cfg.interfaces != [ ];
        message = "vpn-control-web requires explicit private networks and firewall interfaces.";
      }
    ];
    networking.firewall.interfaces = lib.genAttrs cfg.interfaces (_: {
      allowedTCPPorts = [ cfg.port ];
    });
    services.caddy.enable = true;
    services.caddy.virtualHosts."https://${cfg.hostAddress}:${toString cfg.port}".extraConfig = ''
      bind ${cfg.hostAddress}
      tls internal
      @outside not remote_ip ${lib.concatStringsSep " " cfg.allowedNetworks}
      route {
        respond @outside 403
        header {
          X-Content-Type-Options nosniff
          Referrer-Policy no-referrer
          X-Frame-Options DENY
          Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'self'; object-src 'none'"
        }
        handle /api/* {
          reverse_proxy 127.0.0.1:${toString cfg.apiPort}
        }
        handle {
          root * ${cfg.package}
          header Cache-Control no-cache
          try_files {path} /index.html
          file_server
        }
      }
    '';
  };
}
