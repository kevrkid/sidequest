# Gyms and fitness for the map's 🏋️ Gyms layer, from OpenStreetMap: gyms and fitness studios, climbing gyms, yoga
# and pilates, boxing and martial arts, CrossFit boxes, spin studios, dance studios, ice rinks and rec centers.
# Writes data/gyms.json (name, kind, position, address, hours, website, phone, chain).
#
#   ruby fetch_gyms.rb        # under a minute; slow links: just run it again
#
# Left out: places with no name, and private ones (apartment, hotel, office and school gyms).
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'

BBOX = '29.85,-98.15,30.65,-97.40'   # Round Rock to San Marcos, Lake Travis to the east side (same as Outdoors)
OUT = File.join(__dir__, 'data', 'gyms.json')
MIRRORS = %w[https://overpass-api.de/api/interpreter https://overpass.kumi.systems/api/interpreter
             https://overpass.private.coffee/api/interpreter].freeze

def fetch(q)
  delay = 3
  6.times do |attempt|
    uri = URI(MIRRORS[attempt % MIRRORS.size])
    begin
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 150) do |http|
        req = Net::HTTP::Post.new(uri, 'User-Agent' => 'SideQuest/1.0 (gyms for a local events app)')
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

FIT = 'fitness|climbing|bouldering|yoga|pilates|boxing|martial_arts|karate|taekwondo|judo|jiu-jitsu|brazilian_jiu-jitsu|mma|kickboxing|muay_thai|crossfit|cycling|spinning|dance|ice_hockey|ice_skating|swimming|basketball|volleyball|multi'
QUERY = <<~Q
  [out:json][timeout:120];
  (
    nwr["leisure"="fitness_centre"](#{BBOX});
    nwr["leisure"="sports_centre"](#{BBOX});
    nwr["leisure"="ice_rink"](#{BBOX});
    nwr["amenity"="dojo"](#{BBOX});
    nwr["leisure"="dance"](#{BBOX});
    nwr["sport"~"^(#{FIT})(;|$)"]["leisure"~"sports_hall|fitness_station"](#{BBOX});
  );
  out center tags;
Q

PRIVATE = /\b(apartments?|residen\w*|condos?|lofts?|villas?|living|senior|hotel|inn|suites|marriott|hilton|hyatt|office|campus|employee|staff|fire station|police|elementary|middle school|high school|isd|amli|camden|greystar|clubhouse|hoa|poa)\b/i
# Sports centres that aren't gyms (unless the name also says gym / fitness / rec center / rink)
NOT_GYM = /\b(tennis|pool|swim\w*|aquatics?|natatorium|soccer|baseball|softball|football|fields?|complex|paintball|golf|sportsplex|youth|little league|stadium|exercise station|fitness station|fitness trail|courts?|pickleball|skatepark|disc golf)\b/i
GYMISH = /\b(gym\w*|fitness|athletic club|rec(reation)? cent(er|re)|community cent(er|re)|activity cent(er|re)|ymca|ywca|hockey|ice|rink)\b/i
# Never a gym for this layer: pools, courts, shooting and country clubs, and kids' gymnastics (the app leaves kids' stuff out)
NEVER = /\b(pools?|tennis|courts?|rifle|guns?|shooting|country club|golf|gymnastics|tumbl\w*|kids|tots|swim\w*|aquatics?|body shop|fitness station|exercise station)\b/i
FITSPORT = /fitness|climbing|bouldering|yoga|pilates|boxing|martial|karate|taekwondo|judo|jiu|mma|kickbox|muay|crossfit|cycling|spinning|dance|ice_hockey|ice_skating/
# Rinks OpenStreetMap doesn't have yet: geocoded from their address (one Nominatim lookup each per run)
EXTRA = [{ 'name' => 'Chaparral Ice', 'kind' => 'rink', 'addr' => '2525 W Anderson Ln, Austin, TX 78757', 'sports' => %w[ice_hockey ice_skating],
           'web' => 'https://apps.daysmartrecreation.com/dash/x/#/online/chaparralice/calendar' }].freeze

# What kind of place it is, from its tags and name (the first that fits).
def kind_of(t)
  sport = t['sport'].to_s.downcase
  name = t['name'].to_s.downcase
  return 'rink' if t['leisure'] == 'ice_rink' || sport =~ /ice_hockey|ice_skating/ || name =~ /\bice\b|rink|hockey/
  return 'climbing' if sport =~ /climbing|bouldering/ || name =~ /climb|boulder|crag/
  return 'crossfit' if sport =~ /crossfit/ || name =~ /crossfit/
  return 'yoga' if sport =~ /yoga|pilates/ || name =~ /yoga|pilates|barre/
  return 'boxing' if t['amenity'] == 'dojo' || sport =~ /boxing|martial|karate|taekwondo|judo|jiu|mma|kickbox|muay/ ||
                     name =~ /box|karate|jiu|jitsu|bjj|mma|martial|taekwondo|kung fu|muay|krav|dojo|fight/
  return 'cycling' if sport =~ /cycling|spinning/ || name =~ /cycle|spin\b|soulcycle|cyclebar/
  return 'dance' if t['leisure'] == 'dance' || sport =~ /dance/ || name =~ /danc/
  return 'rec' if name =~ /rec(reation|retion)? cent(er|re)|community cent(er|re)|activity cent(er|re)|ymca/ ||
                  (t['leisure'] == 'sports_centre' && t['operator'].to_s =~ /city of|parks|county/i)
  return 'rec' if t['leisure'] == 'sports_centre' && sport =~ /swimming|basketball|volleyball|multi/
  'gym'
end

CHAINS = /\A(planet fitness|24 hour fitness|la fitness|gold'?s gym|life ?time|crunch|anytime fitness|orangetheory|f45|snap fitness|eos fitness|world gym|equinox|onelife|chuze|club pilates|corepower yoga|pure barre|title boxing|9round|ufc gym|row house|stretchlab|burn boot camp|ymca|esporta|youfit|vasa)/i

def norm(s) s.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip end

elements = fetch(QUERY)
puts "#{elements.size} raw"
gyms = []
elements.each do |e|
  t = e['tags'] || {}
  name = t['name'].to_s.strip
  next if name.empty? || name =~ PRIVATE
  next if %w[private no members].include?(t['access'])
  next if t['leisure'] == 'sports_centre' && t['building'] == 'school'
  next if name =~ NEVER || (name =~ NOT_GYM && name !~ GYMISH)
  next if %w[sports_centre sports_hall].include?(t['leisure']) && name !~ GYMISH && t['sport'].to_s !~ FITSPORT   # a ballfield complex, not a gym
  lat = e['lat'] || e.dig('center', 'lat')
  lng = e['lon'] || e.dig('center', 'lon')
  next unless lat && lng
  addr = [[t['addr:housenumber'], t['addr:street']].compact.join(' '), t['addr:city']].reject { |x| x.to_s.empty? }.join(', ')
  web = t['website'] || t['contact:website']
  web = "https://#{web}" if web && web !~ %r{\Ahttps?://}i
  sports = t['sport'].to_s.split(';').map(&:strip).reject(&:empty?).first(4)
  gyms << { 'id' => "gy#{e['type'][0]}#{e['id']}", 'name' => name[0, 80], 'kind' => kind_of(t),
            'lat' => lat.round(6), 'lng' => lng.round(6), 'addr' => addr.empty? ? nil : addr, 'hours' => t['opening_hours'],
            'web' => web, 'phone' => t['phone'] || t['contact:phone'], 'sports' => sports,
            'chain' => (name =~ CHAINS || (t['brand'] && t['brand:wikidata'])) ? true : nil }.compact
end

def geocode(q)
  uri = URI("https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(q: q, format: 'json', limit: 1, countrycodes: 'us')}")
  r = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |h| h.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (gyms)') }
  hit = JSON.parse(r.body).first
  sleep 1.1   # Nominatim: one request a second
  hit && [hit['lat'].to_f.round(6), hit['lon'].to_f.round(6)]
rescue StandardError => e
  warn "    geocode #{q}: #{e.message[0, 60]}"
  nil
end

EXTRA.each do |x|
  next if gyms.any? { |g| norm(g['name']) == norm(x['name']) }
  ll = geocode(x['addr']) or next
  gyms << x.merge('id' => "gyx#{norm(x['name']).tr(' ', '-')}", 'lat' => ll[0], 'lng' => ll[1])
end

# The same gym mapped twice (a point and its building): same name within ~120 m, keep the one with more details.
kept = []
gyms.sort_by { |g| -g.size }.each do |g|
  dup = kept.find { |k| norm(k['name']) == norm(g['name']) && ((k['lat'] - g['lat']).abs * 111_000 < 120 && (k['lng'] - g['lng']).abs * 96_000 < 120) }
  kept << g unless dup
end
kept.sort_by! { |g| [g['kind'], g['name']] }

FileUtils.mkdir_p(File.dirname(OUT))
File.write(OUT, JSON.generate({ 'fetched' => Time.now.utc.iso8601, 'source' => 'OpenStreetMap contributors (ODbL)', 'gyms' => kept }))
puts "#{kept.size} gyms → #{OUT}"
puts kept.group_by { |g| g['kind'] }.map { |k, v| "#{k} #{v.size}" }.sort.join(' · ')
