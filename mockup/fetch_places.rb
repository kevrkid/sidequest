#!/usr/bin/env ruby
# Downloads food & drink places (Round Rock to South Austin) from OpenStreetMap's Overpass API into
# data/places.json, which the server reads. Run it by hand or weekly; the app never downloads on
# its own.
#
#   ruby fetch_places.rb            # resume: only tiles not downloaded yet
#   ruby fetch_places.rb --fresh    # weekly refresh: re-download every tile
#   ruby fetch_places.rb --merge    # no downloading: rebuild places.json from the tiles saved so far
#
# Slow or flaky connection? The area is split into small tiles saved one at a time under
# data/places_tiles/, so an interrupted run picks up where it left off. Short timeouts, retries
# with backoff, and three Overpass mirrors.
require 'json'
require 'time'
require 'net/http'
require 'uri'
require 'fileutils'
require 'set'
$stdout.sync = true

ROOT = __dir__
TILE_DIR = File.join(ROOT, 'data', 'places_tiles')
OUT = File.join(ROOT, 'data', 'places.json')
SOUTH, NORTH, WEST, EAST = 30.12, 30.60, -97.95, -97.55   # South Austin .. Round Rock
STEP = 0.04                                                 # ~4 km tiles, small enough for a phone hotspot
MIRRORS = %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter
             https://overpass.private.coffee/api/interpreter]
AMENITY = 'restaurant|fast_food|cafe|bar|pub|nightclub|biergarten|food_court|ice_cream'

def query(s, w, n, e)
  bb = "#{s},#{w},#{n},#{e}"
  <<~Q
    [out:json][timeout:40];
    (nwr["amenity"~"^(#{AMENITY})$"]["name"](#{bb}); nwr["shop"~"^(bakery|coffee)$"]["name"](#{bb}););
    out center tags;
  Q
end

def fetch(q)
  delay = 3
  6.times do |attempt|
    mirror = MIRRORS[attempt % MIRRORS.size]
    begin
      uri = URI(mirror)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 75) do |http|
        req = Net::HTTP::Post.new(uri, 'User-Agent' => 'SideQuest/1.0 (places for a local events app)')
        req.set_form_data('data' => q)
        http.request(req)
      end
      raise "HTTP #{res.code}" unless res.code == '200'
      return JSON.parse(res.body)['elements']   # parsing fails on a cut-off download, which retries
    rescue StandardError => e
      warn "    #{URI(mirror).host}: #{e.class.name.split('::').last} #{e.message[0, 60]}; retry in #{delay}s"
      sleep delay
      delay = [delay * 2, 60].min
    end
  end
  nil
end

KIND = lambda do |t|
  a = t['amenity']; n = t['name'].to_s
  return 'food truck' if t['street_vendor'] == 'yes' || n =~ /\b(food )?truck\b|\btrailer\b/i && %w[fast_food restaurant].include?(a)
  return 'truck park' if a == 'food_court' && n =~ /truck|park/i
  { 'restaurant' => 'restaurant', 'fast_food' => 'fast food', 'cafe' => 'cafe', 'bar' => 'bar', 'pub' => 'pub',
    'nightclub' => 'club', 'biergarten' => 'beer garden', 'food_court' => 'food hall', 'ice_cream' => 'ice cream' }[a] ||
    { 'bakery' => 'bakery', 'coffee' => 'cafe' }[t['shop']] || 'restaurant'
end

# Local first. National chains are left out, except a short list of popular ones people actually ask
# for. A place counts as a chain when OpenStreetMap gives its brand a Wikidata id (small local brands
# don't have one), or when it shares its name with such a brand. Names are matched by prefix after
# norm(), so "Torchy's Tacos" and "Torchys" both hit 'torchys'.
def norm(s)
  s.to_s.downcase.unicode_normalize(:nfkd).gsub(/[^a-z0-9]/, '').sub(/\Athe/, '')
end

AUSTIN = %w[juiceland pterrys torchys amysicecream chuys hopdoddy thundercloud pluckers kerbeylane tacodeli
            pinthouse ramentatsuya tarka jackallens summermoon mightyfine hatcreek elpollorico].freeze   # Austin-born: count as local
TEXAS = %w[whataburger tacocabana schlotzskys shipley goldenchick bushschicken rudys saltgrass chickenexpress
           laynes tacopalenque lubys fuzzys jasonsdeli freebirds gattis doubledaves twinpeaks hteao whichwich
           mooyah velvettaco dimassis lupetortilla mainevent kolachefactory billmillers pappas cottonpatch southsidemarket].freeze
KEEP = %w[chilis olivegarden applebees cheesecakefactory texasroadhouse ihop dennys wafflehouse redlobster bjs
          buffalowildwings longhorn pfchangs crackerbarrel redrobin yardhouse davebusters hooters firstwatch
          kurasushi fogodechao ruthschris carrabbas cheddars snooze chickfila innout raisingcanes shakeshack].freeze
def listed?(list, n)
  list.any? { |k| n.start_with?(k) }
end

def chain_of(t, brands)
  n = norm(t['brand'] || t['name'])
  return nil if listed?(AUSTIN, n)
  return 'texas' if listed?(TEXAS, n)
  return nil unless (t['brand'] && t['brand:wikidata']) || brands.include?(norm(t['name']))
  listed?(KEEP, n) ? 'national' : 'drop'
end

def place_of(e, brands)
  t = e['tags'] || {}
  lat = e['lat'] || e.dig('center', 'lat'); lng = e['lon'] || e.dig('center', 'lon')
  return nil unless t['name'] && lat
  chain = chain_of(t, brands)
  return nil if chain == 'drop'
  addr = [[t['addr:housenumber'], t['addr:street']].compact.join(' '), t['addr:city']].reject { |x| x.to_s.empty? }.join(', ')
  {
    'id' => "#{e['type'][0]}#{e['id']}", 'name' => t['name'], 'kind' => KIND.call(t),
    'cuisine' => t['cuisine'].to_s.downcase.split(/[;,]/).map(&:strip).reject(&:empty?),
    'hours' => t['opening_hours'], 'addr' => addr.empty? ? nil : addr,
    'lat' => lat.round(5), 'lng' => lng.round(5),
    'web' => t['website'] || t['contact:website'], 'menu' => t['website:menu'] || t['menu:url'] || t['menu'] =~ %r{\Ahttps?://} && t['menu'],
    'phone' => t['phone'] || t['contact:phone'], 'chain' => chain
  }.reject { |_, v| v.nil? || v == [] }
end

fresh = ARGV.include?('--fresh')
merge_only = ARGV.include?('--merge')
FileUtils.mkdir_p(TILE_DIR)
tiles = []
lat = SOUTH
while lat < NORTH
  lng = WEST
  while lng < EAST
    tiles << [lat.round(2), lng.round(2), [lat + STEP, NORTH].min.round(2), [lng + STEP, EAST].min.round(2)]
    lng += STEP
  end
  lat += STEP
end

done = 0
tiles.each_with_index do |(s, w, n, e), i|
  file = File.join(TILE_DIR, "#{s}_#{w}.json")
  if File.exist?(file) && !fresh
    done += 1
    next
  end
  next if merge_only
  print format('tile %3d/%d  %.2f,%.2f … ', i + 1, tiles.size, s, w)
  els = fetch(query(s, w, n, e))
  if els
    File.write("#{file}.tmp", JSON.generate(els))
    File.rename("#{file}.tmp", file)
    done += 1
    puts "#{els.size} places"
  else
    puts 'gave up for now (run again to retry)'
  end
  sleep 1.2   # be polite to the free servers
end

raw = Dir[File.join(TILE_DIR, '*.json')].flat_map { |f| JSON.parse(File.read(f)) }
brands = raw.map { |e| e['tags'] || {} }.select { |t| t['brand'] && t['brand:wikidata'] }.map { |t| norm(t['brand']) }.to_set
places = {}
dropped = 0
raw.each { |e| (p = place_of(e, brands)) ? places[p['id']] = p : (dropped += 1 if chain_of(e['tags'] || {}, brands) == 'drop') }
list = places.values.sort_by { |p| p['name'].downcase }
File.write("#{OUT}.tmp", JSON.generate('fetched' => Time.now.utc.iso8601, 'source' => 'OpenStreetMap contributors (ODbL)',
                                       'tiles' => "#{done}/#{tiles.size}", 'places' => list))
File.rename("#{OUT}.tmp", OUT)
with_hours = list.count { |p| p['hours'] }
puts "\n#{done}/#{tiles.size} tiles · #{list.size} places · #{with_hours} with opening hours (#{(100.0 * with_hours / [list.size, 1].max).round}%)"
puts list.group_by { |p| p['kind'] }.map { |k, v| "#{k} #{v.size}" }.sort.join(' · ')
puts "#{list.count { |p| !p['chain'] }} local · #{list.count { |p| p['chain'] == 'texas' }} Texas chains · #{list.count { |p| p['chain'] == 'national' }} popular national chains kept · #{dropped} other national chains left out"
puts done < tiles.size ? 'Some tiles are missing: run again to finish.' : "Saved #{OUT}"
