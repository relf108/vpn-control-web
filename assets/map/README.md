# Offline relay atlas data

- `relay_locations.json`: public city coordinates from
  https://api.mullvad.net/app/v1/relays, retrieved 2026-11-10. Coordinates describe
  cities, not individual server buildings or the live tunnel endpoint. No account,
  device, or user location data is included. Refresh this reviewed snapshot when
  adding cities. Unknown/custom relay IDs remain selectable through the dropdown.
- `world_land.geojson`: Natural Earth 1:110m land outline, public domain.
  Source: https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_land.geojson
  Terms: https://www.naturalearthdata.com/about/terms-of-use/

Both files are bundled with the app. Rendering makes no map-service, tile,
geolocation, or provider requests. Only relays returned by the authenticated API
appear as selectable dots; bundled coordinates never expand the relay allowlist.
