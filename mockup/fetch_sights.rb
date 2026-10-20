# Sights & history for the map and Scout: Texas Historical Commission markers (with their full text), National
# Register buildings, Wikipedia articles about places (summary + photo), and OpenStreetMap museums, viewpoints,
# monuments and public art. Writes data/sights.json.
#
#   ruby fetch_sights.rb          # ~15 minutes the first time (one page per marker); reruns reuse data/sights_cache/
#   ruby fetch_sights.rb --merge  # rebuild sights.json from the cache without downloading
#
# Credits shown in the app: marker text © Texas Historical Commission (public record); Wikipedia text is CC BY-SA
# (link back to the article); OpenStreetMap data ODbL.
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
require 'cgi'
require 'time'

BOX = [29.85, -98.15, 30.65, -97.40]   # Round Rock to San Marcos, Lake Travis to the east side (same as outdoors)
OUT = File.join(__dir__, 'data', 'sights.json')
CACHE = File.join(__dir__, 'data', 'sights_cache')
MERGE = ARGV.include?('--merge')
UA = 'SideQuest/1.0 (sights and local history for an Austin events app; kevrkid@gmail.com)'
FileUtils.mkdir_p(File.join(CACHE, 'markers'))

def get(url, tries: 4)
  delay = 2
  tries.times do
    uri = URI(url)
    begin
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 15, read_timeout: 120) do |h|
        h.request(Net::HTTP::Get.new(uri, 'User-Agent' => UA))
      end
      return res.body if res.code == '200'
      raise "HTTP #{res.code}"
    rescue StandardError => e
      warn "    #{uri.host}: #{e.message[0, 60]}; retry in #{delay}s"
      sleep delay; delay *= 2
    end
  end
  nil
end

def cached(name)
  f = File.join(CACHE, name)
  return JSON.parse(File.read(f)) if File.exist?(f)
  return nil if MERGE
  v = yield
  File.write(f, JSON.generate(v)) unless v.nil?
  v
end

def in_box?(la, ln) la.between?(BOX[0], BOX[2]) && ln.between?(BOX[1], BOX[3]) end

def km(a, b, c, d)
  dy = (a - c) * 110.57; dx = (b - d) * 111.32 * Math.cos(a * Math::PI / 180)
  Math.hypot(dx, dy)
end

def norm(s) s.to_s.downcase.gsub(/&/, 'and').gsub(/\(.*?\)/, '').gsub(/[^a-z0-9]+/, ' ').sub(/\A(the|site of the|site of) /, '').strip end

# ---- Texas Historical Commission: shapefile tables (DBF) out of the Atlas downloads
def dbf_rows(zip, inner)
  path = File.join(CACHE, zip)
  unless File.exist?(path)
    abort "No #{zip} in the cache (run without --merge)." if MERGE
    body = get("https://atlas.thc.texas.gov/staticFile/#{zip}") or abort "Could not download #{zip}."
    File.binwrite(path, body)
  end
  f = IO.popen(['unzip', '-p', path, inner], 'rb', &:read)
  n, hl, rl = f[4, 4].unpack1('V'), f[8, 2].unpack1('v'), f[10, 2].unpack1('v')
  fields = []; o = 32
  while f.getbyte(o) != 0x0d
    fields << [f[o, 11].delete("\0"), f.getbyte(o + 16)]; o += 32
  end
  Array.new(n) do |i|
    r = f[hl + i * rl, rl]; p = 1
    fields.map { |nm, l| v = r[p, l].to_s.force_encoding('ISO-8859-1').encode('UTF-8').strip; p += l; [nm, v] }.to_h
  end
end

LABELS = ['Marker Number', 'Atlas Number', 'Marker Title', 'Index Entry', 'Address', 'City', 'County', 'UTM Zone', 'UTM Easting',
          'UTM Northing', 'Subject Codes', 'Marker Year', 'Recorded Texas Historic Landmark', 'Marker Location',
          'Private Property', 'Marker Condition', 'Marker Size', 'Marker Text', 'Location Map'].freeze
# Pages cached by an older version of this script ran some fields together; cut them at the next label.
def tidy(v) v.to_s.sub(/ (Index Entry|UTM Zone|Private Property|Marker Condition|Marker Size) .*\z/m, '').strip end
def marker_page(atlas)
  html = get("https://atlas.thc.texas.gov/Details/#{atlas}") or return nil
  t = html.gsub(%r{<script.*?</script>|<style.*?</style>}m, '').gsub(/<[^>]+>/, "\n")
  lines = CGI.unescapeHTML(t).split("\n").map(&:strip).reject(&:empty?)
  out = {}
  LABELS.each do |lab|
    i = lines.index(lab) or next
    j = (i + 1...lines.size).find { |k| LABELS.include?(lines[k]) } || lines.size
    out[lab] = lines[i + 1...j].join(' ')
  end
  out
end

sights = []
puts 'Texas historical markers'
markers = dbf_rows('HistoricalMarkers_shp.zip', 'HistoricalMarkers/HistoricalMarkers.dbf')
             .select { |r| in_box?(r['LATITUDE'].to_f, r['LONGITUDE'].to_f) }
markers.each_with_index do |r, i|
  atlas = r['ATLAS_NUM'].to_f.round.to_s
  m = (cached("markers/#{atlas}.json") { sleep 0.4; marker_page(atlas) } || {}).transform_values { |v| tidy(v) }
  print "\r  #{i + 1}/#{markers.size}" if (i % 10).zero?
  text = m['Marker Text'].to_s.gsub(/\s+/, ' ').strip
  sights << { id: "m#{atlas}", kind: 'marker', name: m['Marker Title'].to_s.empty? ? r['NAME'] : m['Marker Title'],
              lat: r['LATITUDE'].to_f.round(5), lng: r['LONGITUDE'].to_f.round(5), year: m['Marker Year'].to_s[/\d{4}/]&.to_i,
              addr: [m['Address'], m['City']].reject { |x| x.to_s.empty? }.join(', '), where: m['Marker Location'],
              topics: m['Subject Codes'], rthl: m['Recorded Texas Historic Landmark'] == 'Yes', text: text,
              src: 'thc', url: "https://atlas.thc.texas.gov/Details/#{atlas}" }.reject { |_, v| v.nil? || v == '' }
end
puts "\n  #{sights.size} markers, #{sights.count { |s| s[:text] }} with text"

puts 'National Register of Historic Places'
nr = dbf_rows('NationalRegisterPT_shp.zip', 'NationalRegisterPT/NationalRegisterPT.dbf')
       .select { |r| in_box?(r['LAT'].to_f, r['LON'].to_f) }
nr.reject! { |r| r['RESNAME'] =~ /\(Gone\)/i }   # listed places that no longer stand
seen = Hash.new(0)
nr.each do |r|
  n = (seen[r['REFNUM']] += 1)   # one listing can have several points (the moonlight towers): number them
  sights << { id: "nr#{r['REFNUM']}#{n > 1 ? "-#{n}" : ''}", kind: 'landmark', name: r['RESNAME'], lat: r['LAT'].to_f.round(5), lng: r['LON'].to_f.round(5),
              addr: [r['ADDRESS'], r['CITY']].reject(&:empty?).join(', '), listed: r['LISTED_DAT'][0, 4].to_i,
              src: 'nrhp', url: "https://atlas.thc.texas.gov/Details/#{r['ATLAS_NUM'].to_f.round}" }
end
puts "  #{nr.size} listed places"

# ---- Wikipedia: every article with coordinates in the area, kept when it's about a place worth visiting
puts 'Wikipedia'
SKIP_DESC = /restaurant|neighbou?rhood|school|college\b|station|hospital|tournament|company|election|team\b|organi[sz]ation|radio|television|newspaper|census|unincorporated|city in|town in|village|county|apartment|residential|office|corporation|headquarters|mall|shopping|street in|road in|highway|interchange|airport|power plant|reservoir dam|bus |rail|prison|jail|subdivision|data cent|^$/i
pages = {}
lat = BOX[0] + 0.06
while lat < BOX[2]
  lng = BOX[1] + 0.07
  while lng < BOX[3]
    key = format('wiki_%.2f_%.2f.json', lat, lng)
    got = cached(key) do
      sleep 0.3
      body = get("https://en.wikipedia.org/w/api.php?action=query&format=json&generator=geosearch&ggscoord=#{lat}%7C#{lng}" \
                 '&ggsradius=10000&ggslimit=500&colimit=max&prop=coordinates%7Cdescription%7Cpageprops&ppprop=wikibase_item')
      body && (JSON.parse(body).dig('query', 'pages') || {}).values
    end
    (got || []).each { |p| pages[p['pageid']] ||= p }
    lng += 0.14
  end
  lat += 0.12
end
keep = pages.values.select do |p|
  c = (p['coordinates'] || [])[0] or next false
  in_box?(c['lat'], c['lon']) && p['description'].to_s !~ SKIP_DESC
end
puts "  #{pages.size} articles, #{keep.size} about places to see"
keep.map { |p| p['pageid'] }.each_slice(20).with_index do |ids, i|
  ex = cached("wikitext_#{ids.first}_#{ids.size}.json") do
    sleep 0.3
    body = get("https://en.wikipedia.org/w/api.php?action=query&format=json&prop=extracts%7Cpageimages%7Cinfo&inprop=url" \
               "&exintro=1&explaintext=1&exchars=1200&exlimit=20&piprop=thumbnail&pithumbsize=480&pilimit=20&pageids=#{ids.join('%7C')}")
    body && JSON.parse(body).dig('query', 'pages')
  end || {}
  print "\r  summaries #{(i + 1) * 20}/#{keep.size}"
  ex.each_value do |e|
    p = pages[e['pageid']] or next
    c = p['coordinates'][0]
    d = p['description'].to_s
    kind = case d
           when /museum|gallery|library/i then 'museum'
           when /sculpture|statue|mural|artwork|public art|fountain/i then 'art'
           when /park|garden|preserve|lake|river|creek|spring|pool|cave|greenbelt|falls|trail|cemetery/i then 'nature'
           when /venue|theat(er|re)|music|club|arena|stadium|concert|amphitheat/i then 'venue'
           when /historic|monument|memorial|church|house|building|bridge|tower|hotel|mansion|capitol|fort|landmark|district/i then 'landmark'
           else 'sight'
           end
    sights << { id: "w#{e['pageid']}", kind: kind, name: e['title'], lat: c['lat'].round(5), lng: c['lon'].round(5), what: d,
                text: e['extract'].to_s.gsub(/\s+/, ' ').strip, photo: e.dig('thumbnail', 'source'),
                src: 'wikipedia', url: e['fullurl'] || "https://en.wikipedia.org/?curid=#{e['pageid']}" }.reject { |_, v| v.nil? || v == '' }
  end
end
puts

# ---- OpenStreetMap: museums, viewpoints, attractions, monuments, statues, public art
puts 'OpenStreetMap'
q = "[out:json][timeout:120];(nwr[\"tourism\"~\"^(attraction|museum|viewpoint|gallery|zoo|artwork)$\"][\"name\"](#{BOX.join(',')});" \
    "nwr[\"historic\"~\"^(monument|ruins|building|castle|fort|tomb|heritage|house|railway|city_gate|church)$\"][\"name\"](#{BOX.join(',')});" \
    "nwr[\"historic\"=\"memorial\"][\"memorial\"~\"^(statue|war_memorial|stone|obelisk|sculpture)$\"][\"name\"](#{BOX.join(',')}););out center tags;"
osm = cached('osm.json') do
  got = nil
  %w[overpass.kumi.systems overpass-api.de overpass.private.coffee].each do |host|
    uri = URI("https://#{host}/api/interpreter")
    req = Net::HTTP::Post.new(uri, 'User-Agent' => UA)
    req.set_form_data('data' => q)
    res = (Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 150) { |h| h.request(req) } rescue nil)
    if res&.code == '200'
      got = JSON.parse(res.body)['elements']
      break
    end
    warn "    #{host}: #{res ? res.code : 'no answer'}"
    sleep 5
  end
  got
end
osm = [] unless osm.is_a?(Array)
osm.each do |el|
  t = el['tags']; la = el['lat'] || el.dig('center', 'lat'); ln = el['lon'] || el.dig('center', 'lon')
  next unless la
  kind = case t['tourism']
         when 'museum', 'gallery' then 'museum'
         when 'viewpoint' then 'view'
         when 'artwork' then 'art'
         when 'zoo' then 'nature'
         else t['historic'] ? 'landmark' : 'sight'
         end
  kind = 'art' if t['memorial'] == 'statue' || t['memorial'] == 'sculpture'
  sights << { id: "o#{el['type'][0]}#{el['id']}", kind: kind, name: t['name'], lat: la.round(5), lng: ln.round(5),
              text: t['description'] || t['inscription'], web: t['website'], src: 'osm',
              wiki: t['wikipedia'] }.reject { |_, v| v.nil? || v == '' }
end
puts "  #{osm.size} places"

# ---- merge duplicates: the same place from two sources within ~250 m with the same name keeps the richest one.
# Markers stay separate (their text is the plaque itself) but take the Wikipedia photo of the building they're on.
RANK = { 'wikipedia' => 0, 'nrhp' => 1, 'osm' => 2 }
merged = []
by_name = Hash.new { |h, k| h[k] = [] }
sights.sort_by { |s| [s[:src] == 'thc' ? 1 : 0, RANK[s[:src]] || 3] }.each do |s|
  next merged << s if s[:src] == 'thc'
  k = norm(s[:name])
  twin = by_name[k].find { |o| km(o[:lat], o[:lng], s[:lat], s[:lng]) < 0.25 }
  if twin
    twin[:listed] ||= s[:listed]; twin[:addr] ||= s[:addr]; twin[:web] ||= s[:web]
    twin[:text] ||= s[:text]
    twin[:nrhp] = true if s[:src] == 'nrhp'
    twin[:kind] = s[:kind] if twin[:kind] == 'sight'
  else
    s[:nrhp] = true if s[:src] == 'nrhp'
    by_name[k] << s; merged << s
  end
end
merged.select { |s| s[:src] == 'thc' && !s[:photo] }.each do |m|
  k = norm(m[:name])
  twin = by_name[k].find { |o| o[:photo] && km(o[:lat], o[:lng], m[:lat], m[:lng]) < 0.3 }
  m[:photo] = twin[:photo] if twin
end
merged.reject! { |s| s[:name].to_s.empty? }
merged.each { |s| s[:text] = s[:text][0, 1200] if s[:text] }

FileUtils.mkdir_p(File.dirname(OUT))
tmp = "#{OUT}.tmp"
File.write(tmp, JSON.generate(built: Time.now.utc.iso8601, sights: merged))
File.rename(tmp, OUT)
counts = merged.group_by { |s| s[:kind] }.transform_values(&:size)
puts "Wrote #{merged.size} sights to #{OUT} (#{(File.size(OUT) / 1024.0).round} KB): #{counts}"
