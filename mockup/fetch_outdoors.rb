# Nature and water areas for the map's Outdoors layer, from OpenStreetMap: parks, greenbelts and preserves
# (green), lakes and river stretches (blue), with their real outlines, plus the spots that matter on the water and
# trail: kayak / paddleboard rentals, boat ramps and put-ins, fishing spots, trailheads. Writes data/outdoors.json.
#
#   ruby fetch_outdoors.rb        # a few minutes; slow links: just run it again
#
# Outlines are simplified (~15 m) so the whole file stays small enough for a phone.
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'

BBOX = '29.85,-98.15,30.65,-97.40'   # Round Rock to San Marcos, Lake Travis to the east side
OUT = File.join(__dir__, 'data', 'outdoors.json')
MIRRORS = %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter
             https://overpass.private.coffee/api/interpreter].freeze
MIN_GREEN_KM2 = 0.12   # skip pocket parks and playgrounds
MIN_WATER_KM2 = 0.10

def fetch(q)
  delay = 3
  6.times do |attempt|
    uri = URI(MIRRORS[attempt % MIRRORS.size])
    begin
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 150) do |http|
        req = Net::HTTP::Post.new(uri, 'User-Agent' => 'SideQuest/1.0 (outdoor areas for a local events app)')
        req.set_form_data('data' => q)
        http.request(req)
      end
      raise "HTTP #{res.code}" unless res.code == '200'
      return JSON.parse(res.body)['elements']
    rescue StandardError => e
      warn "    #{uri.host}: #{e.class.name.split('::').last} #{e.message[0, 60]}; retry in #{delay}s"
      sleep delay
      delay = [delay * 2, 60].min
    end
  end
  abort 'Could not reach OpenStreetMap. Try again later.'
end

# ---- geometry
def area_km2(ring)   # shoelace on a local flat projection; fine at city scale
  lat0 = ring.sum { |p| p[0] } / ring.size * Math::PI / 180
  pts = ring.map { |la, ln| [ln * 111.32 * Math.cos(lat0), la * 110.57] }
  pts.each_cons(2).sum { |(x1, y1), (x2, y2)| x1 * y2 - x2 * y1 }.abs / 2
end

def simplify(pts, tol)   # Douglas-Peucker, iterative
  return pts if pts.size < 4
  keep = Array.new(pts.size, false); keep[0] = keep[-1] = true
  stack = [[0, pts.size - 1]]
  until stack.empty?
    a, b = stack.pop
    (ax, ay), (bx, by) = pts[a], pts[b]
    dx, dy = bx - ax, by - ay; len = Math.hypot(dx, dy)
    far, idx = 0, nil
    (a + 1...b).each do |i|
      px, py = pts[i]
      d = len.zero? ? Math.hypot(px - ax, py - ay) : ((px - ax) * dy - (py - ay) * dx).abs / len
      far, idx = d, i if d > far
    end
    next unless idx && far > tol
    keep[idx] = true
    stack << [a, idx] << [idx, b]
  end
  pts.select.with_index { |_, i| keep[i] }
end

# Relation members are separate ways; join them end to end into closed rings.
def rings_of(el)
  return [el['geometry'].map { |g| [g['lat'], g['lon']] }] if el['type'] == 'way'
  parts = (el['members'] || []).select { |m| m['type'] == 'way' && m['role'] != 'inner' && m['geometry'] }
                               .map { |m| m['geometry'].map { |g| [g['lat'], g['lon']] } }
  rings = []
  until parts.empty?
    ring = parts.shift
    loop do
      break if ring.first == ring.last && ring.size > 3
      i = parts.index { |p| p.first == ring.last || p.last == ring.last }
      break unless i
      p = parts.delete_at(i)
      ring += (p.first == ring.last ? p : p.reverse)[1..]
    end
    rings << ring if ring.size > 3
  end
  rings
end

def shape(el, tol = 0.00015)
  rings = rings_of(el).map { |r| simplify(r, tol).map { |la, ln| [la.round(5), ln.round(5)] } }.select { |r| r.size >= 4 }
  return nil if rings.empty?
  km2 = rings.sum { |r| area_km2(r) }
  big = rings.max_by { |r| area_km2(r) }
  { rings: rings, km2: km2.round(2), c: [(big.sum { |p| p[0] } / big.size).round(5), (big.sum { |p| p[1] } / big.size).round(5)] }
end

def near?(spot, area, km)   # within `km` of the area's outline or centre (cheap and good enough for tagging)
  pts = area[:rings].flatten(1).each_slice(3).map(&:first) + [area[:c]]
  pts.any? { |la, ln| Math.hypot((la - spot[:lat]) * 110.57, (ln - spot[:lng]) * 96.0) < km }
end

# ---- download
# One Overpass query from a list of selectors, each limited to the area
def query(selectors, out)
  "[out:json][timeout:180];(#{selectors.map { |x| "#{x}(#{BBOX});" }.join});#{out}"
end

warn 'Spots: rentals, ramps, put-ins, fishing, trailheads…'
spots = fetch(query(['nwr["amenity"="boat_rental"]', 'nwr["leisure"="slipway"]', 'nwr["canoe"="put_in"]', 'nwr["leisure"="fishing"]',
                     'node["highway"="trailhead"]', 'nwr["shop"~"^(boat|outdoor|sports)$"]["name"~"kayak|paddle|SUP|canoe",i]'], 'out center tags;')).map do |e|
  t = e['tags'] || {}; la = e['lat'] || e.dig('center', 'lat'); ln = e['lon'] || e.dig('center', 'lon')
  next unless la
  kind = if t['amenity'] == 'boat_rental' || t['shop'] then 'rental'
         elsif t['leisure'] == 'fishing' then 'fishing'
         elsif t['highway'] == 'trailhead' then 'trailhead'
         else 'launch'
         end
  { id: "#{e['type'][0]}#{e['id']}", name: t['name'].to_s.empty? ? nil : t['name'], kind: kind, lat: la.round(5), lng: ln.round(5),
    web: t['website'] || t['contact:website'] }.compact
end.compact.uniq { |s| [s[:kind], s[:lat].round(4), s[:lng].round(4)] }
warn "  #{spots.size} spots"

warn 'Green areas: parks, greenbelts, preserves…'
green = fetch(query(['way["leisure"~"^(park|nature_reserve)$"]["name"]', 'relation["leisure"~"^(park|nature_reserve)$"]["name"]',
                     'way["boundary"="protected_area"]["name"]', 'relation["boundary"="protected_area"]["name"]'], 'out geom qt;'))
warn "  #{green.size} named parks and preserves (small ones are dropped below)"
warn 'Water: lakes, reservoirs, river stretches…'
water = fetch(query(['way["natural"="water"]["name"]', 'relation["natural"="water"]["name"]', 'way["water"~"^(river|lake|reservoir)$"]["name"]'], 'out geom qt;'))
warn "  #{water.size} named water bodies"
warn 'Hike & bike trails…'
trail_ways = fetch(query(['way["highway"~"^(cycleway|path|footway|track|bridleway)$"]["name"~"trail|greenbelt|hike|bike|pathway|loop",i]'], 'out geom qt;'))
warn "  #{trail_ways.size} named trail segments"
warn 'Rivers (paddling lines)…'
rivers = fetch(query(['way["waterway"="river"]["name"]'], 'out geom qt;'))
warn "  #{rivers.size} river segments"

HIKE = /greenbelt|preserve|trail|wilderness|nature|natural area|state park|metro park|wildlife|canyon|hike|bluff|refuge/i
areas = []
{ 'green' => green, 'water' => water }.each do |kind, els|
  els.each do |el|
    t = el['tags'] || {}
    next if kind == 'water' && (t['water'] =~ /pond|wastewater|basin|reflecting|pool/i || t['name'] =~ /\Apond\b|soil conservation|detention|retention|wastewater|treatment/i)
    s = shape(el) or next
    next if s[:km2] < (kind == 'green' ? MIN_GREEN_KM2 : MIN_WATER_KM2)
    areas << s.merge(id: "#{el['type'][0]}#{el['id']}", name: t['name'], kind: kind)
  end
end
areas.uniq! { |a| [a[:name], a[:c].map { |x| x.round(2) }] }

# Trails: join each named trail's segments into simplified lines; biking where any part is a cycleway or allows bikes.
trail_ways.group_by { |w| w.dig('tags', 'name') }.each do |name, ways|
  lines = ways.map { |w| simplify(w['geometry'].map { |g| [g['lat'], g['lon']] }, 0.00012).map { |la, ln| [la.round(5), ln.round(5)] } }.select { |l| l.size >= 2 }
  km = lines.sum { |l| l.each_cons(2).sum { |(a, b), (c, d)| Math.hypot((c - a) * 110.57, (d - b) * 96.0) } }
  next if km < 1
  bike = ways.any? { |w| t = w['tags']; t['highway'] == 'cycleway' || %w[yes designated permissive].include?(t['bicycle']) } || name =~ /bike/i
  mid = lines.max_by(&:size)
  areas << { id: "t#{ways.first['id']}", name: name, kind: 'trail', lines: lines, km: km.round(1), km2: 0, c: mid[mid.size / 2],
             acts: bike ? %w[hiking biking] : %w[hiking] }
end

# Rivers are lines in OpenStreetMap: join each river's segments by name into simplified polylines (blue lines).
rivers.group_by { |w| w.dig('tags', 'name') }.each do |name, ways|
  lines = ways.map { |w| simplify(w['geometry'].map { |g| [g['lat'], g['lon']] }, 0.0002).map { |la, ln| [la.round(5), ln.round(5)] } }.select { |l| l.size >= 2 }
  km = lines.sum { |l| l.each_cons(2).sum { |(a, b), (c, d)| Math.hypot((c - a) * 110.57, (d - b) * 96.0) } }
  next if km < 3   # creeks' short named stubs
  # OpenStreetMap tags many small (often dry) creeks as rivers: keep real rivers, and creeks with a launch or rental on them
  launch = spots.any? { |sp| %w[launch rental].include?(sp[:kind]) && lines.flatten(1).each_slice(4).map(&:first).any? { |la, ln| Math.hypot((la - sp[:lat]) * 110.57, (ln - sp[:lng]) * 96.0) < 0.6 } }
  next unless name =~ /\briver\b/i || launch
  mid = lines.max_by(&:size)
  areas << { id: "r#{ways.first['id']}", name: name, kind: 'river', lines: lines, km: km.round(1), km2: 0, c: mid[mid.size / 2] }
end

# What you can do there: from the area itself and the spots around it.
areas.each do |a|
  next if a[:kind] == 'trail'   # tagged above
  acts = []
  if a[:kind] == 'river'
    near = spots.select { |s| a[:lines].flatten(1).each_slice(4).map(&:first).any? { |la, ln| Math.hypot((la - s[:lat]) * 110.57, (ln - s[:lng]) * 96.0) < 0.6 } }
    acts.push('fishing', 'kayak', 'canoe')
    acts << 'paddleboard' if near.any? { |s| s[:kind] == 'rental' }
  elsif a[:kind] == 'water'
    acts << 'fishing'
    near = spots.select { |s| near?(s, a, 0.6) }
    paddle = near.any? { |s| %w[rental launch].include?(s[:kind]) } || a[:name] =~ /lake|river|creek/i
    acts.push('paddleboard', 'kayak', 'canoe') if paddle
  else
    near = spots.select { |s| near?(s, a, 0.4) }
    acts << 'hiking' if a[:name] =~ HIKE || near.any? { |s| s[:kind] == 'trailhead' } || a[:km2] > 1
    acts << 'nature'
    acts << 'fishing' if near.any? { |s| s[:kind] == 'fishing' }
  end
  a[:acts] = acts.uniq
end

areas.sort_by! { |a| -a[:km2] }
FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, JSON.generate(fetched: Time.now.utc.iso8601, source: 'OpenStreetMap contributors (ODbL)', areas: areas, spots: spots))
warn "Wrote #{OUT}: #{areas.count { |a| a[:kind] == 'green' }} green areas, #{areas.count { |a| a[:kind] == 'water' }} water areas, " \
     "#{areas.count { |a| a[:kind] == 'river' }} rivers, #{areas.count { |a| a[:kind] == 'trail' }} trails, " \
     "#{spots.size} spots, #{(File.size(OUT) / 1024.0).round} KB"
