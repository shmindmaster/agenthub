# Places

## Find places

```bash
node scripts/brave.mjs places "coffee" --location "san francisco ca united states"
node scripts/brave.mjs places "pizza" --latitude 40.7128 --longitude -74.006 --radius 1500
node scripts/brave.mjs places --location "tokyo japan" --count 20
```

- Locate with `--latitude` and `--longitude` together, or a `--location` string (`<city> <state> <country>` in the US, `<city> <country>` elsewhere, lowercase, no commas).
- Omit the query to browse an area. A call with no query and no location fails with `422`.
- `--count` (1-100) is spread across every bucket, so an address query can use the whole budget on `addresses` and `streets`.
- `--radius` is a bias in meters, not a hard cutoff.
- `--geoloc 40.7128x-74.0060` adds `distance` to each result; `--units imperial` changes its unit.

Each result carries `id`, `title`, `description`, address, `coordinates`, rating, phone and current-day hours, so most questions need no second call.

## Details

POI ids stay valid for about 8 hours.

```bash
node scripts/brave.mjs pois <id> <id>            # reviews, full hours, contact (up to 20 ids)
node scripts/brave.mjs descriptions <id> <id>    # short generated descriptions
```

Add `--loc-lat` and `--loc-long` to `pois` for distances.
