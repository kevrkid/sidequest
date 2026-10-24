# "Add location" when posting (stories, flares, live): every named place we know in one list — food & drink
# (places.rb), sights & history (sights.rb), parks, lakes and trails (outdoors.json), farmers markets and
# neighborhoods (areas.rb). Nearest first with nothing typed; best name match (then nearest, then best known)
# when something is. Places anywhere else ("an address, another city") come from OpenStreetMap's free geocoder,
# only when someone asks for it.
require 'json'

module Spots
  @lock = Mutex.new
  @built = nil   # [signature, list]

  # kind => [emoji, label]
  KINDS = {
    'restaurant' => ['🍽️', 'Restaurant'], 'fast food' => ['🍔', 'Fast food'], 'cafe' => ['☕', 'Coffee shop'], 'bar' => ['🍸', 'Bar'],
    'pub' => ['🍺', 'Pub'], 'bakery' => ['🥐', 'Bakery'], 'ice cream' => ['🍦', 'Ice cream'], 'food truck' => ['🚚', 'Food truck'],
    'club' => ['🪩', 'Nightclub'], 'food hall' => ['🍱', 'Food hall'], 'truck park' => ['🚚', 'Food truck park'], 'beer garden' => ['🍻', 'Beer garden'],
    'landmark' => ['🏛️', 'Landmark'], 'museum' => ['🖼️', 'Museum'], 'art' => ['🎨', 'Public art'], 'nature' => ['🌳', 'Nature'],
    'venue' => ['🎤', 'Venue'], 'view' => ['🌄', 'Viewpoint'], 'sight' => ['📸', 'Sight'], 'marker' => ['🪧', 'Historical marker'],
    'green' => ['🌳', 'Park'], 'trail' => ['🥾', 'Trail'], 'river' => ['🏞️', 'River'], 'water' => ['🌊', 'Lake'],
    'launch' => ['🛶', 'Boat launch'], 'trailhead' => ['🥾', 'Trailhead'], 'rental' => ['🛶', 'Rentals'], 'fishing' => ['🎣', 'Fishing spot'],
    'market' => ['🧺', "Farmers' market"], 'area' => ['🏘️', 'Neighborhood']
  }.freeze
  # Kinds people rarely post from: shown only when they match what was typed, or very close by.
  QUIET = %w[marker launch fishing].freeze
  # Suggestions with nothing typed lean toward places people go (food, drink, parks, venues) over plaques and statues
  # nobody posts from, unless those are well known. In km of extra distance.
  BACKSEAT = { 'landmark' => 0.45, 'sight' => 1.0, 'art' => 0.5, 'marker' => 1.0, 'trail' => 0.2 }.freeze

  module_function

  def fold(s)
    s.to_s.dup.force_encoding('UTF-8').scrub('').unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase
     .gsub('&', ' and ').gsub(/['’.]/, '').gsub(/[^a-z0-9]+/, ' ').strip
  end

  def km(a, b, c, d)
    dy = (a - c) * 110.57; dx = (b - d) * 111.32 * Math.cos(a * Math::PI / 180)
    Math.hypot(dx, dy)
  end

  def file(env, name)
    ENV[env] ? File.join(__dir__, ENV[env]) : File.join(__dir__, 'data', name)
  end

  def read(env, name, key)
    JSON.parse(File.read(file(env, name)))[key] || []
  rescue StandardError
    []
  end

  # One entry per place: [id, name, kind, lat, lng, folded name, popularity, address]
  def list
    places = Places.data[:list]; sights = Sights.list; areas = Areas.list
    sig = [places.object_id, sights.object_id, areas.object_id,
           *%w[SQ_OUTDOORS_FILE:outdoors.json SQ_MARKETS_FILE:markets.json].map { |x| (File.mtime(file(*x.split(':'))).to_f rescue 0) }]
    @lock.synchronize do
      return @built[1] if @built && @built[0] == sig
      out = []
      add = ->(id, name, kind, lat, lng, addr = nil) do
        next if name.to_s.strip.empty? || !lat || !lng
        out << [id, name.to_s.strip.sub(/\s*\((austin|texas|austin, texas|tx)\)\z/i, ''), kind, lat.to_f, lng.to_f, fold(name), Popular[id.split(':', 2)[1]], addr]
      end
      places.each { |p| add.("p:#{p['id']}", p['name'], p['kind'], p['lat'], p['lng'], p['addr']) }
      towns = areas.map { |a| fold(a['name']) } + ['austin', 'greater austin', 'austin texas', 'travis county']
      sights.each { |s| add.("s:#{s['id']}", s['name'], s['kind'], s['lat'], s['lng']) unless towns.include?(fold(s['name'])) }   # Wikipedia's "Greater Austin" is not a spot
      read('SQ_OUTDOORS_FILE', 'outdoors.json', 'areas').each { |a| add.("o:#{a['id']}", a['name'], a['kind'], *Array(a['c'])) }
      read('SQ_OUTDOORS_FILE', 'outdoors.json', 'spots').each do |s|
        next if s['name'].to_s =~ /\A(boat launch|boat ramp|trailhead|fishing( pier)?)\z/i   # nameless in all but name
        add.("o:#{s['id']}", s['name'], s['kind'], s['lat'], s['lng'])
      end
      read('SQ_MARKETS_FILE', 'markets.json', 'markets').each { |m| add.("m:#{m['id']}", m['name'], 'market', m['lat'], m['lng'], m['addr']) }
      areas.each { |a| add.("a:#{fold(a['name']).tr(' ', '-')}", a['name'], 'area', a['lat'], a['lng']) }
      @built = [sig, out]
      out
    end
  end

  def row(s, near)
    e, label = KINDS.fetch(s[2], ['📍', s[2].to_s.capitalize])
    { id: s[0], name: s[1], e: e, kind: label, lat: s[3].round(5), lng: s[4].round(5), addr: s[7] || (area_at(s[3], s[4])&.dig('name') unless s[2] == 'area'),
      km: near && km(near[0], near[1], s[3], s[4]).round(2) }.compact
  end

  # The neighborhood a point is in (closest centre within its radius), for "Hyde Park, Austin".
  def area_at(lat, lng)
    Areas.list.map { |a| [km(lat, lng, a['lat'], a['lng']) / (a['r'] || 1.0).to_f, a] }.select { |x, _| x <= 1.3 }.min_by(&:first)&.last
  end

  # near: [lat, lng], rounded to ~100 m by the caller.
  def search(q, near: nil, limit: 40)
    words = fold(q).split.first(6)
    all = list
    rows =
      if words.empty?
        return { results: [] } unless near
        all.map do |s|
          d = km(near[0], near[1], s[3], s[4])
          next if d > 3 || s[2] == 'area' || (QUIET.include?(s[2]) && d > 0.3)
          [d + (s[6] >= 40 ? 0 : BACKSEAT.fetch(s[2], 0)) - s[6] / 100.0 * 0.25, s]
        end.compact
      else
        phrase = words.join(' ')
        all.map do |s|
          name = s[5]; toks = name.split
          next unless words.all? { |w| toks.any? { |t| t.start_with?(w) } || (w.size >= 4 && name.include?(w)) }
          d = near ? km(near[0], near[1], s[3], s[4]) : 5
          score = (name == phrase ? 0 : name.start_with?(phrase) ? 1 : toks.each_cons(words.size).any? { |c| c.join(' ').start_with?(phrase) } ? 2 : 3) +
                  [d, 40].min * 0.12 - s[6] / 100.0 * 1.5 + (QUIET.include?(s[2]) ? 1.5 : 0) - (s[2] == 'area' ? 0.5 : 0)
          [score, s]
        end.compact
      end
    seen = {}
    # The same place from two lists (Zilker Park the sight and the park outline): keep the better-ranked one.
    out = rows.sort_by(&:first).map(&:last).reject do |s|
      dup = seen[s[5]]&.any? { |o| (d = km(o[3], o[4], s[3], s[4])) < 0.1 || (d < 3 && o[0][0, 2] != s[0][0, 2]) }   # two Starbucks a mile apart are two places
      (seen[s[5]] ||= []) << s
      dup
    end
    here = near && area_at(*near)
    { results: out.first(limit).map { |s| row(s, near) }, area: here && { name: here['name'], lat: here['lat'], lng: here['lng'] } }
  end
end

# Anywhere else: an address, a town, a place we don't list. Nominatim allows 1 request a second and no
# search-as-you-type, so the app calls this only when someone taps "Search everywhere".
SPOT_GEO = {}
def spots_anywhere(q, near)
  key = "#{q.downcase}|#{near&.map { |x| x.round(1) }&.join(',')}"
  SPOT_GEO[key] ||= GEO_LOCK.synchronize do
    sleep 1.1
    lat, lng = near || [30.27, -97.74]
    box = [lng - 0.6, lat + 0.5, lng + 0.6, lat - 0.5].join(',')   # around you first, the rest of the world after
    uri = URI("https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(q: q, format: 'json', limit: 8, viewbox: box, addressdetails: 0)}")
    r = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (tagging a post with a place)')
    end
    JSON.parse(r.body).map do |x|
      parts = x['display_name'].to_s.split(',').map(&:strip)
      { id: "g:#{x['osm_type'].to_s[0]}#{x['osm_id']}", name: parts.first.to_s[0, 80], addr: parts[1, 3].to_a.join(', ')[0, 120], e: '📍',
        kind: x['type'].to_s.tr('_', ' ').capitalize, lat: x['lat'].to_f.round(5), lng: x['lon'].to_f.round(5) }
    end
  end
  SPOT_GEO.shift while SPOT_GEO.size > 500
  SPOT_GEO[key]
end

# A post's or a stream's place: a built-in venue id, or {name, lat, lng} picked with "Add location".
def spot_ref(v)
  return v.to_s[0, 20] if v.is_a?(String) || v.is_a?(Symbol)
  return nil unless v.is_a?(Hash)
  lat = Float(v['lat']) rescue nil
  lng = Float(v['lng']) rescue nil
  name = v['name'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 60]
  return nil if name.empty? || !lat || !lng || !lat.between?(-90, 90) || !lng.between?(-180, 180)
  { 'name' => name, 'lat' => lat.round(5), 'lng' => lng.round(5), 'id' => v['id'].to_s[0, 40], 'e' => v['e'].to_s[0, 4],
    'kind' => v['kind'].to_s[0, 40] }.reject { |_, x| x == '' }
end

def mount_spots(server)
  route(server, '/api/spots', auth: false, get: true) do |_b, _h, req|
    limit!("spots:#{client_ip(req)}", 900, 3600)
    lat, lng = req.query['lat'].to_f, req.query['lng'].to_f
    near = lat.between?(-90, 90) && lng.between?(-180, 180) && !(lat.zero? && lng.zero?) ? [lat.round(3), lng.round(3)] : nil   # ~100 m: close enough for "here", never exact GPS
    q = req.query['q'].to_s[0, 60]
    if req.query['anywhere'] == '1'
      raise 'Type a place or an address.' if q.strip.size < 3
      limit!("spotsgeo:#{client_ip(req)}", 40, 3600)
      { results: spots_anywhere(q.strip, near) }
    else
      Spots.search(q, near: near, limit: (req.query['limit'] || 40).to_i.clamp(1, 80))
    end
  end
end
