"""Food, drink and venues from Overture Maps (open data: overturemaps.org, CDLA Permissive 2.0 / ODbL by source) for
the same area as fetch_places.rb. Writes data/overture.json; `ruby fetch_places.rb --merge` folds it into places.json
(OpenStreetMap wins where both have a place; chains, duplicates and closed places are dropped there).

A tool for this Mac only (the app never runs it). One-time setup, then run it every month or two:

  python3 -m venv ~/.sidequest-data && ~/.sidequest-data/bin/pip install duckdb
  ~/.sidequest-data/bin/python fetch_overture.py            # latest release (~30 s)
  ~/.sidequest-data/bin/python fetch_overture.py 2026-10-21.0

Reads Overture's public GeoParquet on S3 in place (only the row groups inside the box), no account needed.
"""
import json, os, re, sys, time, urllib.request

import duckdb

S, N, W, E = 29.80, 30.72, -98.15, -97.39          # keep in step with fetch_places.rb
MIN_CONF = 0.65                                     # Overture's own "is this real" score
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'overture.json')
# Overture categories (taxonomy.primary / basic_category) worth having, beyond food & drink: places people go out to.
VENUES = {'music_venue', 'jazz_and_blues', 'comedy_club', 'theatre', 'theatre_venue', 'performing_arts_venue', 'opera_and_ballet',
          'movie_theater', 'cinema', 'drive_in_theater', 'karaoke', 'bowling_alley', 'arcade', 'pool_billiards', 'gaming_venue',
          'escape_rooms', 'axe_throwing', 'mini_golf', 'dance_club', 'night_club', 'lounge', 'brewery', 'winery', 'distillery',
          'beer_garden', 'cocktail_bar', 'wine_bar', 'sports_bar', 'pub', 'bar', 'hookah_bar'}


def latest_release():
    with urllib.request.urlopen('https://overturemaps-us-west-2.s3.amazonaws.com/?list-type=2&prefix=release/&delimiter=/', timeout=30) as r:
        rel = re.findall(r'<Prefix>release/([^<]+)/</Prefix>', r.read().decode())
    return sorted(rel)[-1]


def main():
    release = sys.argv[1] if len(sys.argv) > 1 else latest_release()
    t = time.time()
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs; SET s3_region='us-west-2';")
    venues = ','.join(f"'{v}'" for v in sorted(VENUES))
    rows = con.execute(f"""
      SELECT id, names."primary", taxonomy."primary", basic_category, taxonomy.hierarchy, confidence, operating_status,
             (bbox.ymin + bbox.ymax) / 2, (bbox.xmin + bbox.xmax) / 2,
             addresses[1].freeform, addresses[1].locality, websites[1], phones[1], socials, brand.names."primary", brand.wikidata
      FROM read_parquet('s3://overturemaps-us-west-2/release/{release}/theme=places/type=place/*', hive_partitioning=1)
      WHERE bbox.xmin BETWEEN {W} AND {E} AND bbox.ymin BETWEEN {S} AND {N} AND confidence >= {MIN_CONF}
        AND coalesce(operating_status, 'open') NOT ILIKE '%closed%'
        AND (list_contains(taxonomy.hierarchy, 'food_and_drink') OR taxonomy."primary" IN ({venues}) OR basic_category IN ({venues}))
    """).fetchall()
    out = []
    for (oid, name, cat, basic, hier, conf, _st, lat, lng, addr, city, web, phone, socials, brand, wikidata) in rows:
        if not name:
            continue
        ig = next((s for s in (socials or []) if 'instagram.com' in s), None)
        out.append({k: v for k, v in {
            'id': oid, 'name': name.strip(), 'cat': cat, 'basic': basic, 'hier': hier or [], 'conf': round(conf, 2),
            'lat': round(lat, 6), 'lng': round(lng, 6), 'addr': ', '.join(x for x in (addr, city) if x) or None,
            'web': web, 'phone': phone, 'ig': ig, 'brand': brand, 'brand_wd': wikidata}.items() if v not in (None, '', [])})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT + '.tmp', 'w') as f:
        json.dump({'release': release, 'fetched': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                   'source': 'Overture Maps Foundation (overturemaps.org)', 'bbox': [S, W, N, E], 'places': out}, f, separators=(',', ':'))
    os.replace(OUT + '.tmp', OUT)
    print(f'{len(out)} places from Overture {release} in {time.time() - t:.0f}s → {OUT}')


if __name__ == '__main__':
    main()
