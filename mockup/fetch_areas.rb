# Austin's neighborhoods, main streets and nearby towns, so Scout can answer "a good spot in Hyde Park" or "in Cedar
# Park": each name is placed with OpenStreetMap's geocoder (checked: the right kind of place, inside the Austin area)
# and its size taken from the outline OpenStreetMap returns. Writes data/areas.json.
#
#   ruby fetch_areas.rb
require 'json'
require_relative 'geofix'

OUT = File.join(__dir__, 'data', 'areas.json')
# name, what to look up, other names people use
AREAS = [
  ['Hyde Park', 'Hyde Park, Austin, Texas'], ['Mueller', 'Mueller, Austin, Texas'],
  ['Clarksville', 'Clarksville, Austin, Texas'], ['Zilker', 'Zilker, Austin, Texas'],
  ['Travis Heights', 'Travis Heights, Austin, Texas'], ['Holly', 'Holly, Austin, Texas'], ['Montopolis', 'Montopolis, Austin, Texas'],
  ['Downtown Austin', 'Downtown, Austin, Texas', ['downtown']], ['West Campus', 'West Campus, Austin, Texas'],
  ['Tarrytown', 'Tarrytown, Austin, Texas'], ['Rosedale', 'Rosedale, Austin, Texas'], ['Allandale', 'Allandale, Austin, Texas'],
  ['Crestview', 'Crestview, Austin, Texas'], ['Brentwood', 'Brentwood, Austin, Texas'], ['Windsor Park', 'Windsor Park, Austin, Texas'],
  ['Cherrywood', 'Cherrywood, Austin, Texas'], ['Govalle', 'Govalle, Austin, Texas'], ['East Cesar Chavez', 'East Cesar Chavez, Austin, Texas'],
  ['St. Elmo', 'St. Elmo, Austin, Texas', ['st elmo', 'saint elmo']], ['Barton Hills', 'Barton Hills, Austin, Texas'], ['Circle C', 'Circle C Ranch, Austin, Texas', ['circle c ranch']],
  ['Westlake', 'West Lake Hills, Texas', ['west lake hills', 'westlake hills']], ['Rollingwood', 'Rollingwood, Texas'],
  ['Riverside', 'East Riverside, Austin, Texas', ['east riverside']], ['Highland', 'Highland, Austin, Texas'], ['Wells Branch', 'Wells Branch, Texas'],
  ['Anderson Mill', 'Anderson Mill, Texas'], ['Jollyville', 'Jollyville, Texas'], ['Arboretum', 'The Arboretum, Austin, Texas', ['the arboretum']],
  ['Cedar Park', 'Cedar Park, Texas'], ['Round Rock', 'Round Rock, Texas'], ['Pflugerville', 'Pflugerville, Texas'], ['Georgetown', 'Georgetown, Texas'],
  ['Leander', 'Leander, Texas'], ['Bee Cave', 'Bee Cave, Texas'], ['Lakeway', 'Lakeway, Texas'], ['Dripping Springs', 'Dripping Springs, Texas'],
  ['Buda', 'Buda, Texas'], ['Kyle', 'Kyle, Texas'], ['San Marcos', 'San Marcos, Texas'], ['Manor', 'Manor, Texas'], ['Hutto', 'Hutto, Texas'],
  ['Sunset Valley', 'Sunset Valley, Texas'], ['Lockhart', 'Lockhart, Texas'], ['Wimberley', 'Wimberley, Texas'], ['Bastrop', 'Bastrop, Texas'],
  ['Lago Vista', 'Lago Vista, Texas'], ['Spicewood', 'Spicewood, Texas'], ['Elgin', 'Elgin, Texas']
].freeze
# Streets people call areas: a stretch, not the whole road (centre and how far it runs)
STRETCHES = [
  ['South Lamar', [30.2515, -97.7650], 1.6, ['s lamar', 'south lamar blvd']],
  ['South First', [30.2470, -97.7560], 1.4, ['s 1st', 'south 1st', 's first']],
  ['South Congress', [30.2500, -97.7495], 1.2, ['s congress', 'south congress ave', 'soco']],
  ['Burnet Road', [30.3330, -97.7390], 2.0, ['burnet rd', 'burnet']],
  ['East Sixth', [30.2640, -97.7270], 0.9, ['e 6th', 'east 6th']],
  ['Manor Road', [30.2850, -97.7150], 0.9, ['manor rd']],
  ['North Lamar', [30.3350, -97.7240], 2.0, ['n lamar']],
  ['The Drag', [30.2880, -97.7420], 0.7, ['guadalupe', 'the drag']],
  # neighborhoods OpenStreetMap only finds under another name (checked by hand, October 2026)
  ['North Loop', [30.31788, -97.71876], 1.0, []],
  ['Bouldin Creek', [30.25567, -97.75548], 1.2, ['bouldin']],
  ['Oak Hill', [30.23431, -97.86877], 2.5, []]
].freeze
KINDS = %w[neighbourhood suburb quarter city town village hamlet residential administrative boundary city_block locality].freeze

def look(q)
  sleep 1.1   # OpenStreetMap's rule: one request a second
  uri = URI("https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(q: q, format: 'json', limit: 5, countrycodes: 'us')}")
  r = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (Austin neighborhoods for Scout)') }
  want = Geofix.norm(q.split(',').first).split - %w[the]
  JSON.parse(r.body).find do |x|
    Geofix.in_box?(x['lat'], x['lon']) && (KINDS.include?(x['type']) || KINDS.include?(x['addresstype'])) &&
      want.all? { |w| Geofix.norm(x['display_name'].split(',').first).split.include?(w) }
  end
rescue StandardError => e
  warn "  #{q}: #{e.message}"; nil
end

def km(a, b, c, d) Math.hypot((a - c) * 110.57, (b - d) * 111.32 * Math.cos(a * Math::PI / 180)) end

areas = AREAS.map do |name, q, aka|
  x = look(q)
  next warn("  skipped #{name}: no match for #{q}") unless x
  la, ln = x['lat'].to_f, x['lon'].to_f
  s, n, w, e = x['boundingbox'].map(&:to_f)
  r = (km(s, w, n, e) / 2).clamp(0.6, 8.0).round(1)   # half the outline's diagonal
  r = 1.0 if r.between?(1.4, 1.6) && %w[neighbourhood residential].include?(x['type'])   # no outline, just OpenStreetMap's default box
  puts "  #{name.ljust(18)} #{la.round(4)},#{ln.round(4)}  r #{r} km  (#{x['type']})"
  { name: name, aka: aka || [], lat: la.round(5), lng: ln.round(5), r: r }
end.compact   # Ruby 2.6: no filter_map
areas += STRETCHES.map { |name, (la, ln), r, aka| { name: name, aka: aka, lat: la, lng: ln, r: r } }
File.write(OUT, JSON.pretty_generate(areas: areas))
puts "wrote #{areas.size} areas to #{OUT}"
