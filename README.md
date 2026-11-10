# vpn-control-web

Flutter web control room for the private [vpn-control API](https://github.com/relf108/vpn-control).
Includes login, passive device discovery, selected/global timed bypass and
restore, approved Mullvad relay selection, status, and manual/minutely refresh.
Destructive or privacy-reducing actions require confirmation.

Gateway status includes a clickable **VPN access** notice showing remaining
account credit as `years / months / days` (for example, `0y / 2m / 14d remaining`).
It uses whole UTC calendar units, handles leap years/month ends, and does not round
partial days up. Expired, unavailable, unconfigured and stale data are labelled
explicitly. Clicking opens `https://mullvad.net/en/account/login` in a new tab;
no credential is included in the URL. Automatic checks require the API's optional
`mullvadAccountFile` runtime credential; this frontend never receives the account
number. Preview dates are simulated, not live account checks.

The offline relay atlas shows public city locations for approved API relays.
Click a dot or use the relay list to select a destination, then confirm with
**Change relay**. Zoom/pan helps separate nearby cities. Gold highlights the
requested destination, not the live tunnel endpoint. Configured defaults and
custom relays without known coordinates remain available in the list; the map
does not guess their locations. The bundled Natural Earth outline and Mullvad
city snapshot make no external tile, geolocation, or map-service requests.
See `assets/map/README.md` for data provenance and attribution.

## NixOS

Add this flake and the API flake as inputs, following the host's nixpkgs. Import
both `nixosModules.default` modules, then configure:

```nix
services.homelab-vpn-control = {
  enable = true;
  credentialsFile = "/var/lib/vpn-control/api-auth.json";
  profileFile = "/var/lib/wireguard/wg-mullvad.conf";
  publicOrigin = "https://192.168.0.100:8443";
};
services.homelab-vpn-web = {
  enable = true;
  hostAddress = "192.168.0.100";
  port = 8443;
  apiPort = 1337;
  allowedNetworks = [ "192.168.0.0/24" "10.77.0.0/24" ];
  interfaces = [ "enp2s0" "wg-home" ];
};
```

Provision the API credential on the target host as described in its README.
This frontend takes **no secrets**. It calls same-origin `/api/v1`, uses the
API's HttpOnly cookie, and keeps CSRF tokens only in memory. Nothing is saved to
localStorage/sessionStorage. All Flutter rendering assets are bundled locally;
no CDN is needed for the UI's standard text. Roboto fonts are bundled under
`assets/fonts` with their Apache license, sourced from the pinned Flutter SDK.
Browser refresh recovers the session from its cookie.

Open `https://192.168.0.100:8443` and trust Caddy's internal CA. Do not forward the
port or add this app to a public Caddy host. Source-network restrictions and
interface-scoped firewall access apply to both static assets and API routes.

The flake exports a static-site package, NixOS module, checks, formatter and
development shell for x86_64-linux/aarch64-linux. Caddy serves the package root
and proxies `/api/*` to the loopback-only API. Change `publicOrigin` to match if
you change the frontend address/port. A package override is available for hosts
that want a separately built frontend.

## Development

```sh
nix develop
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
nix build
```

`flutter run -d web-server` alone does not proxy the API. For authenticated local
integration, use a private HTTPS reverse proxy serving both this app and `/api`,
and set the API `publicOrigin` to that origin. Do not weaken cookie, CSRF, or
origin checks to accommodate an HTTP development server.

After changing dependencies, update both `pubspec.lock` and its JSON equivalent
for the Nix builder: `yq -o=json pubspec.lock > pubspec.lock.json`. Commit both.
`nix build` runs format, analysis, and tests before installing static files.
