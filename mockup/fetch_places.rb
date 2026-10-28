#!/usr/bin/env ruby
# Downloads food & drink places (San Marcos to Georgetown, Lake Travis to Taylor) from OpenStreetMap's Overpass API into
# data/places.json, which the server reads. Run it by hand or weekly; the app never downloads on
# its own.
#
#   ruby fetch_places.rb            # resume: only tiles not downloaded yet
#   ruby fetch_places.rb --fresh    # weekly refresh: re-download every tile
#   ruby fetch_places.rb --merge    # no downloading: rebuild places.json from the tiles saved so far
#   ruby fetch_places.rb --blocks   # when the Overpass servers are slow: ~20 big blocks (0.2°) instead of ~460 tiles
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
SOUTH, NORTH, WEST, EAST = 29.80, 30.72, -98.15, -97.39   # San Marcos .. Georgetown, Lake Travis / Dripping Springs .. Taylor (was 30.12, 30.60, -97.95, -97.55)
STEP = 0.04                                                 # ~4 km tiles, small enough for a phone hotspot
MIRRORS = %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter
             https://overpass.private.coffee/api/interpreter]
AMENITY = 'restaurant|fast_food|cafe|bar|pub|nightclub|biergarten|food_court|ice_cream'

def query(s, w, n, e, timeout = 40)
  bb = "#{s},#{w},#{n},#{e}"
  <<~Q
    [out:json][timeout:#{timeout}];
    (nwr["amenity"~"^(#{AMENITY})$"]["name"](#{bb}); nwr["shop"~"^(bakery|coffee)$"]["name"](#{bb}););
    out center tags;
  Q
end

def fetch(q, read_timeout = 75)
  delay = 3
  6.times do |attempt|
    mirror = MIRRORS[attempt % MIRRORS.size]
    begin
      uri = URI(mirror)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: read_timeout) do |http|
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
            pinthouse ramentatsuya tarka jackallens summermoon mightyfine hatcreek elpollorico tiffstreats teapioca
            smokeymos alamodrafthouse].freeze   # Austin-born: count as local
TEXAS = %w[whataburger tacocabana schlotzskys shipley goldenchick bushschicken rudys saltgrass chickenexpress
           laynes tacopalenque lubys fuzzys jasonsdeli freebirds gattis doubledaves twinpeaks hteao whichwich
           mooyah velvettaco dimassis lupetortilla mainevent kolachefactory billmillers pappas cottonpatch southsidemarket
           mrgattis laredotaco cicis truetexas].freeze
KEEP = %w[chilis olivegarden applebees cheesecakefactory texasroadhouse ihop dennys wafflehouse redlobster bjs
          buffalowildwings longhorn pfchangs crackerbarrel redrobin yardhouse davebusters hooters firstwatch
          kurasushi fogodechao ruthschris carrabbas cheddars snooze chickfila innout raisingcanes shakeshack].freeze
# National chains that often come with no brand tag (Overture especially): left out like any other national chain.
NATIONAL = %w[jerseymikes itsjustwings mayfielddq dairyqueen blackrockcoffee sonicdrive chipotle starbucks dominos littlecaesars
              papajohns popeyes pizzahut subway mcdonalds burgerking wendys tacobell kfc jackinthebox arbys panerabread jimmyjohns
              dunkin krispykreme smoothieking tropicalsmoothie jambajuice firehousesubs potbelly qdoba pandaexpress fiveguys wingstop
              zaxbys culvers menchies freddys papamurphys marcospizza hungryhowies churchschicken longjohnsilvers deltaco elpollo
              loco pandaexpress dutchbros scooterscoffee 7brew baskinrobbins coldstone nothingbundtcakes crumblcookies insomniacookies].freeze
def listed?(list, n)
  list.any? { |k| n.start_with?(k) }
end

def chain_of(t, brands)
  n = norm(t['brand'] || t['name'])
  return nil if listed?(AUSTIN, n)
  return 'texas' if listed?(TEXAS, n)
  return listed?(KEEP, n) ? 'national' : 'drop' if listed?(NATIONAL, n)
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
    'phone' => t['phone'] || t['contact:phone'], 'chain' => chain,
    'food' => (t['food'] if %w[yes no].include?(t['food'])), 'kitchen' => t['opening_hours:kitchen']   # bars: serves food? kitchen hours
  }.reject { |_, v| v.nil? || v == [] }
end

# ---- more places from other open sources, merged after OpenStreetMap (which wins where both have a place) ----
OVERTURE_FILE = File.join(ROOT, 'data', 'overture.json')   # fetch_overture.py
TABC_FILE = File.join(ROOT, 'data', 'tabc.json')           # fetch_tabc.rb
SPEAK_FILE = File.join(ROOT, 'data', 'speakeasies.json')   # hand-kept, from the guides it cites (Austin to Georgetown)
VENUE_KINDS = ['music venue', 'comedy club', 'theater', 'cinema', 'games'].freeze

# Overture category → our kind (nil = not a place to go: candy stores, lottery, bingo...).
def overture_kind(c)
  case c.to_s
  when 'fast_food_restaurant', 'hot_dog_restaurant' then 'fast food'
  when 'food_truck_stand' then 'food truck'
  when 'food_court' then 'food hall'
  when 'coffee_shop', 'cafe', 'tea_room', 'bubble_tea_shop', 'smoothie_juice_bar', 'coffee_roastery', 'non_alcoholic_beverage_venue' then 'cafe'
  when 'bakery', 'donut_shop', 'bagel_shop', 'cupcake_shop', 'pie_shop', 'pretzel_shop', 'macaron_shop' then 'bakery'
  when 'ice_cream_shop', 'dessert_shop', 'frozen_yogurt_shop', 'shaved_ice_shop', 'gelato_shop' then 'ice cream'
  when 'pub', 'gastropub', 'irish_pub' then 'pub'
  when 'beer_garden' then 'beer garden'
  when 'brewery', 'winery', 'distillery', 'cidery', 'wine_tasting_room' then 'brewery'
  when 'dance_club', 'night_club' then 'club'
  when /\A(bar|cocktail_bar|wine_bar|sports_bar|dive_bar|lounge|beer_bar|hookah_bar|gay_bar|speakeasy|cigar_bar|whiskey_bar|tiki_bar|hotel_bar|champagne_bar)\z/ then 'bar'
  when 'music_venue', 'jazz_and_blues_venue', 'jazz_and_blues' then 'music venue'
  when 'comedy_club' then 'comedy club'
  when 'theatre_venue', 'theatre', 'performing_arts_venue', 'opera_and_ballet', 'dinner_theater' then 'theater'
  when 'movie_theater', 'cinema', 'drive_in_theater', 'outdoor_movie_space' then 'cinema'
  when 'arcade', 'bowling_alley', 'pool_billiards', 'karaoke_venue', 'karaoke', 'escape_room', 'escape_rooms', 'axe_throwing', 'mini_golf', 'gaming_venue' then 'games'
  when /_restaurant\z/, 'restaurant', 'diner', 'bistro', 'delicatessen', 'salad_bar', 'soul_food', 'cafeteria', 'tapas_bar', 'sandwich_shop', 'steakhouse' then 'restaurant'
  end
end

# Cuisine from the category name, in OpenStreetMap's words ("mexican_restaurant" → mexican, "texmex_restaurant" → tex-mex).
OV_CUISINE = { 'texmex' => 'tex-mex', 'barbecue' => 'barbecue', 'burger' => 'burger', 'taco' => 'mexican;tacos', 'sandwich_shop' => 'sandwich',
               'bubble_tea_shop' => 'bubble_tea', 'smoothie_juice_bar' => 'juice', 'donut_shop' => 'donut', 'breakfast_and_brunch' => 'breakfast',
               'chicken_wings' => 'wings', 'steakhouse' => 'steak_house', 'sushi' => 'sushi', 'coffee_shop' => 'coffee_shop' }.freeze
def overture_cuisine(c)
  base = c.to_s.sub(/_restaurant\z/, '')
  v = OV_CUISINE[c.to_s] || OV_CUISINE[base] || (c.to_s.end_with?('_restaurant') && base !~ /\A(american|asian|comfort_food|theme|fast_food)\z/ ? base : nil)
  v.to_s.split(';')
end

def miles(a1, o1, a2, o2)
  r = Math::PI / 180
  h = Math.sin((a2 - a1) * r / 2)**2 + Math.cos(a1 * r) * Math.cos(a2 * r) * Math.sin((o2 - o1) * r / 2)**2
  7917.6 * Math.asin(Math.sqrt(h))
end

# A grid of what we have (~500 m cells), so "is it already here?" only looks nearby.
def place_grid(places)
  g = Hash.new { |h, k| h[k] = [] }
  places.each_value { |p| g[[(p['lat'] * 200).floor, (p['lng'] * 200).floor]] << p }
  g
end

def nearby(g, lat, lng)
  ci, cj = (lat * 200).floor, (lng * 200).floor
  [-1, 0, 1].product([-1, 0, 1]).flat_map { |a, b| g[[ci + a, cj + b]] }
end

# Same place, two sources: names that match after norm() (or one starts with the other, 6+ letters), within ~150 m.
def same_place?(p, name, lat, lng, metres = 150)
  a, b = norm(p['name']), norm(name)
  return false if a.empty? || b.empty?
  return false unless miles(p['lat'], p['lng'], lat, lng) * 1609.34 <= metres
  a == b || ([a, b].min_by(&:size).size >= 6 && (a.start_with?(b) || b.start_with?(a))) ||
    ([a, b].min_by(&:size).size >= 9 && (a.include?(b) || b.include?(a)))
end

# Names that aren't a place: an address, the city, a street ("208 W 4th Street", "austin tx", "6th Street Austin, Texas").
NOT_A_NAME = /\A(\d+\s+([nsew]\.?\s+)?[\w.]+(\s+[\w.]+)?\s+(st|street|ave|avenue|blvd|rd|road|dr|drive|lane|ln|way|guadalupe|congress|lamar)\.?|austin,?\s*(tx|texas)?|\d+(st|nd|rd|th) street.*|.*,\s*texas)\z/i
# Venues that are really schools, studios, events, offices or plaques.
NOT_A_VENUE = /\b(academy|schools?|class(es)?|lessons|studios?|high|elementary|isd|department|dept|church|festival|headquarters|hq|wedding|events?|productions?|records|booking|agency|radio|magazine|plaque|historical|rentals?|lot|wrestling|dancers|camp|kids|children'?s|youth|foundation|society|association|league|tours?|throwdowne|bingo|acltv|in the capital)\b/i
# Performing groups and organizers rather than a room you go to, unless the name says it's a building.
NOT_A_ROOM = /\b(opera|symphony|orchestra|chorus|choir|ensemble|alliance|marathon|guild|broadway in|shakespeare|company)\b/i
ROOMISH = /\b(hall|house|theat(er|re)|center|centre|amphitheater|room|club|bar|lounge|stage|playhouse|cinema)\b/i

# A multi-location brand by name ("Sonic Drive-In" starts with the brand "Sonic"), for places with no brand tag.
def brand_prefix?(name, brands)
  n = norm(name)
  n.size >= 5 && brands.any? { |b| b.size >= 5 && n.start_with?(b) }
end

# A few source names are UTF-8 read as Windows-1252 ("CuÃ±ados"): put them back ("Cuñados") when that's what they are.
def demojibake(s)
  return s unless s =~ /[ÃÂ][\u0080-\u00ff]|â€/
  t = s.encode('Windows-1252').force_encoding('UTF-8')
  t.valid_encoding? ? t : s
rescue EncodingError
  s
end

def merge_overture!(places, ov, brands)
  require 'digest'
  st = Hash.new(0)
  g = place_grid(places)
  by_name = places.values.group_by { |p| norm(p['name']) }
  ov.sort_by { |o| -o['conf'].to_f }.each do |o|
    kind = overture_kind(o['cat']) || overture_kind(o['basic'])
    next st['not a place to go'] += 1 unless kind
    next st['not a name / not a venue'] += 1 if o['name'] =~ NOT_A_NAME ||
                                                (VENUE_KINDS.include?(kind) && (o['name'] =~ NOT_A_VENUE || (o['name'] =~ NOT_A_ROOM && o['name'] !~ ROOMISH)))
    chain = chain_of({ 'brand' => o['brand'], 'brand:wikidata' => o['brand_wd'], 'name' => o['name'] }, brands)
    chain ||= chain_of({ 'brand' => o['name'], 'brand:wikidata' => 'Q' }, brands) if brand_prefix?(o['name'], brands)
    chain = 'national' if chain == 'drop' && VENUE_KINDS.include?(kind)   # cinemas, bowling, arcades: chains are where people go
    next st['chains left out'] += 1 if chain == 'drop'
    nn = norm(o['name'])
    # the same specific name within ~3 km is one place listed twice (one copy's position is rough), unless it's a chain
    # ...and the same name at the same street address is one place whatever its pin says (Overture has a few far-off copies)
    addr_key = ->(a) { a.to_s.downcase[/\A\d+\s+[a-z0-9.]+(\s+[a-z0-9.]+)?/].to_s.gsub(/[^a-z0-9]/, '') }
    twin = (by_name[nn] || []).find { |x| (!chain && nn.size >= 8 && miles(x['lat'], x['lng'], o['lat'], o['lng']) <= 1.9) ||
                                          (!addr_key.(x['addr']).empty? && addr_key.(x['addr']) == addr_key.(o['addr'])) }
    if (p = twin || nearby(g, o['lat'], o['lng']).find { |x| same_place?(x, o['name'], o['lat'], o['lng']) || (norm(x['name']) == nn && miles(x['lat'], x['lng'], o['lat'], o['lng']) * 1609.34 <= 400) })
      st['already had'] += 1
      { 'web' => o['web'], 'phone' => o['phone'], 'addr' => o['addr'], 'ig' => o['ig'] }.each { |k, v| p[k] ||= v if v }   # fill blanks only
      next
    end
    p = { 'id' => "o#{Digest::SHA1.hexdigest(o['id'])[0, 11]}", 'name' => demojibake(o['name'])[0, 80], 'kind' => kind, 'cuisine' => overture_cuisine(o['cat']),
          'lat' => o['lat'].round(5), 'lng' => o['lng'].round(5), 'addr' => o['addr'], 'web' => o['web'], 'phone' => o['phone'], 'ig' => o['ig'],
          'chain' => chain, 'src' => 'overture', 'speakeasy' => (o['cat'] == 'speakeasy' ? 'A speakeasy' : nil) }.reject { |_, v| v.nil? || v == [] }
    places[p['id']] = p
    g[[(p['lat'] * 200).floor, (p['lng'] * 200).floor]] << p   # so a second Overture copy of it is caught too
    (by_name[nn] ||= []) << p
    st['added'] += 1
  end
  st
end

# TABC licenses: mark places that serve alcohol (full bar / beer & wine), and add licensed bars no other source has.
BARLIKE = /\b(bar|saloon|pub|tavern|lounge|ice ?house|cantina|cocktails?|tap ?room|taproom|beer|brew\w*|wine|whiskey|whisky|honky[- ]?tonk|dance ?hall|speakeasy|billiards?|pool hall|karaoke|club)\b/i
NOT_A_BAR = /\b(inc|llc|ltd|l\.?p|corp\w*|compan(y|ies)|compa|limited liability|holdings?|hospitality|management|beverages?|catering|events?|hotel|inn|suites|resort|marriott|hilton|hyatt|stadium|arena|center|centre|country club|golf|men'?s club|gentlemen|cabaret|airport|hospital|university|church|lodge \d|vfw|american legion|elks|moose|eagles)\b/i
FOODISH = /\b(restaurant|kitchen|cuisine|grill|bbq|barbecue|noodles?|dumplings?|burgers?|tacos?|taqueria|sushi|pizza\w*|cafe|caf[eé]|bistro|eatery|diner|mexican|indian|thai|italian|seafood|oyster|steak\w*|smokehouse|comida|cocina|food)\b/i
def tabc_name(n)
  n = n.to_s.sub(/\s*[#,]\s*\d+\z/, '').sub(/,?\s+(llc|inc|ltd)\.?\z/i, '').strip
  return n unless n == n.upcase
  n.downcase.split(/(\s+|-|\/)/).map { |w| w =~ /\A(of|and|the|at|on|in|a)\z/ ? w : w.sub(/\A(\w)/) { Regexp.last_match(1).upcase } }.join
   .sub(/\A(\w)/) { Regexp.last_match(1).upcase }.gsub(/\b(Atx|Tx|Bbq|Usa)\b/, &:upcase).gsub(/'S\b/, "'s")
end

# Speakeasies (data/speakeasies.json): mark the place we have (similar name within 150 m) with how to find the door,
# or add it as a bar. id `s` + 11 hex, src 'curated'.
def merge_speakeasies!(places, list)
  require 'digest'
  st = Hash.new(0)
  g = place_grid(places)
  list.each do |s|
    next st['no position'] += 1 unless s['lat'] && s['lng']
    w1 = ->(n) { n.to_s.downcase.sub(/\Athe /, '')[/[a-z0-9']+/].to_s }   # "Kinfolk Lounge & Library" = "Kinfolk Cocktail Lounge & Spirits Library"
    if (p = nearby(g, s['lat'], s['lng']).find { |x| same_place?(x, s['name'], s['lat'], s['lng']) ||
                                                   (w1.(x['name']).size >= 5 && w1.(x['name']) == w1.(s['name']) && miles(x['lat'], x['lng'], s['lat'], s['lng']) * 1609.34 <= 80) })
      p['speakeasy'] = s['how']; p['kind'] = 'bar' unless %w[bar pub club].include?(p['kind'])
      next st['marked'] += 1
    end
    p = { 'id' => "s#{Digest::SHA1.hexdigest(s['name'] + s['addr'].to_s)[0, 11]}", 'name' => s['name'], 'kind' => 'bar', 'lat' => s['lat'].round(5),
          'lng' => s['lng'].round(5), 'addr' => s['addr'], 'speakeasy' => s['how'], 'src' => 'curated' }
    places[p['id']] = p
    g[[(p['lat'] * 200).floor, (p['lng'] * 200).floor]] << p
    st['added'] += 1
  end
  st
end

def merge_tabc!(places, lic, brands)
  require 'digest'
  st = Hash.new(0)
  g = place_grid(places)
  rank = { 'full' => 3, 'beer & wine' => 2, 'beer' => 1 }
  lic.each do |l|
    name = tabc_name(l['name'])
    next st['no name'] += 1 if name.empty?
    if (p = nearby(g, l['lat'], l['lng']).find { |x| same_place?(x, name, l['lat'], l['lng'], 200) })
      p['alcohol'] = l['alcohol'] if rank[l['alcohol']].to_i > rank[p['alcohol']].to_i
      next st['marked'] += 1
    end
    next st['private clubs not added'] += 1 if l['type'] == 'N'   # members only: marks a place, never adds one
    next st['not clearly a bar'] += 1 unless name =~ BARLIKE && name !~ NOT_A_BAR && name !~ NOT_A_NAME
    next st['chains left out'] += 1 if chain_of({ 'name' => name }, brands) == 'drop' || brand_prefix?(name, brands)
    kind = name =~ /billiards?|pool hall|karaoke/i ? 'games' : name =~ /dance ?hall|night ?club/i ? 'club' : name =~ /brew|tap ?room/i ? 'brewery' :
           name =~ FOODISH ? 'restaurant' : 'bar'   # "Mariachis Mexican Restaurant & Bar": a restaurant that serves drinks
    p = { 'id' => "t#{Digest::SHA1.hexdigest(l['id'].to_s)[0, 11]}", 'name' => name[0, 80], 'kind' => kind, 'lat' => l['lat'].round(5),
          'lng' => l['lng'].round(5), 'addr' => l['addr'], 'alcohol' => l['alcohol'], 'src' => 'tabc' }
    places[p['id']] = p
    g[[(p['lat'] * 200).floor, (p['lng'] * 200).floor]] << p
    st['added'] += 1
  end
  st
end

if __FILE__ == $PROGRAM_NAME   # run it; `require` (test_sources.rb) only loads the rules above
fresh = ARGV.include?('--fresh')
merge_only = ARGV.include?('--merge')
FileUtils.mkdir_p(TILE_DIR)
tiles = []
lat = SOUTH
while lat < NORTH - 1e-9   # (repeated += 0.04 lands just under the edge: no zero-height last row)
  lng = WEST
  while lng < EAST - 1e-9
    tiles << [lat.round(2), lng.round(2), [lat + STEP, NORTH].min.round(2), [lng + STEP, EAST].min.round(2)]
    lng += STEP
  end
  lat += STEP
end

# Big blocks (--blocks): fewer, slower requests, for when the public servers time out on every other tile.
BLOCK = 0.2
blocks = []
(0...((NORTH - SOUTH) / BLOCK).ceil).each { |i| (0...((EAST - WEST) / BLOCK).ceil).each { |j| s = (SOUTH + i * BLOCK).round(2); w = (WEST + j * BLOCK).round(2); blocks << [s, w, [s + BLOCK, NORTH].min.round(2), [w + BLOCK, EAST].min.round(2)] } }
block_file = ->(s, w) { File.join(TILE_DIR, "blk_#{s}_#{w}.json") }
if ARGV.include?('--blocks')
  blocks.each_with_index do |(s, w, n, e), i|
    f = block_file.(s, w)
    next if File.exist?(f) && !fresh
    print format('block %2d/%d  %.2f,%.2f … ', i + 1, blocks.size, s, w)
    els = fetch(query(s, w, n, e, 170), 200)
    if els then File.write("#{f}.tmp", JSON.generate(els)); File.rename("#{f}.tmp", f); puts "#{els.size} places"
    else puts 'gave up for now (run again to retry)'
    end
    sleep 2
  end
end
in_block = ->(s, w) { blocks.any? { |bs, bw, bn, be| s >= bs - 1e-9 && w >= bw - 1e-9 && s < bn - 1e-9 && w < be - 1e-9 && File.exist?(block_file.(bs, bw)) } }

done = 0
tiles.each_with_index do |(s, w, n, e), i|
  file = File.join(TILE_DIR, "#{s}_#{w}.json")
  if (File.exist?(file) && !fresh) || in_block.(s, w)
    done += 1
    next
  end
  next if merge_only || ARGV.include?('--blocks')
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
ovr = (JSON.parse(File.read(OVERTURE_FILE)) rescue nil)
brands = raw.map { |e| e['tags'] || {} }.select { |t| t['brand'] && t['brand:wikidata'] }.map { |t| norm(t['brand']) }.to_set
brands.merge((ovr ? ovr['places'] : []).select { |o| o['brand'] && o['brand_wd'] }.map { |o| norm(o['brand']) })   # Overture knows more brands
places = {}
dropped = 0
raw.each { |e| (p = place_of(e, brands)) ? places[p['id']] = p : (dropped += 1 if chain_of(e['tags'] || {}, brands) == 'drop') }
osm_n = places.size
ov_stats = ovr ? merge_overture!(places, ovr['places'], brands) : nil
tabc_stats = (t = (JSON.parse(File.read(TABC_FILE)) rescue nil)) ? merge_tabc!(places, t['licenses'], brands) : nil
speak_stats = (sk = (JSON.parse(File.read(SPEAK_FILE)) rescue nil)) ? merge_speakeasies!(places, sk['speakeasies']) : nil
list = places.values.sort_by { |p| p['name'].downcase }
sources = ['OpenStreetMap contributors (ODbL)']
sources << "Overture Maps Foundation (#{ovr['release']})" if ovr
sources << 'Texas Alcoholic Beverage Commission licenses' if tabc_stats
File.write("#{OUT}.tmp", JSON.generate('fetched' => Time.now.utc.iso8601, 'source' => sources.join('; '),
                                       'tiles' => "#{done}/#{tiles.size}", 'places' => list))
File.rename("#{OUT}.tmp", OUT)
with_hours = list.count { |p| p['hours'] }
puts "\n#{done}/#{tiles.size} tiles · #{list.size} places · #{with_hours} with opening hours (#{(100.0 * with_hours / [list.size, 1].max).round}%)"
puts list.group_by { |p| p['kind'] }.map { |k, v| "#{k} #{v.size}" }.sort.join(' · ')
puts "#{list.count { |p| !p['chain'] }} local · #{list.count { |p| p['chain'] == 'texas' }} Texas chains · #{list.count { |p| p['chain'] == 'national' }} popular national chains kept · #{dropped} other national chains left out"
puts "OpenStreetMap #{osm_n}" + (ov_stats ? " · Overture: #{ov_stats.map { |k, v| "#{k} #{v}" }.join(', ')}" : ' · no data/overture.json (run fetch_overture.py)') +
     (tabc_stats ? " · TABC: #{tabc_stats.map { |k, v| "#{k} #{v}" }.join(', ')}" : '') +
     (speak_stats ? " · speakeasies: #{speak_stats.map { |k, v| "#{k} #{v}" }.join(', ')}" : '')
puts done < tiles.size ? 'Some tiles are missing: run again to finish.' : "Saved #{OUT}"
end
