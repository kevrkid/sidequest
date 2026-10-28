# Food & drink places and venues (data/places.json, written by fetch_places.rb from OpenStreetMap, Overture Maps and
# TABC licenses), with "open now" worked out in Austin time. Searched on the server so Scout and the app get small lists.
require 'json'
require_relative 'hours'
require_relative 'popular'

module Places
  FILE = ENV['SQ_PLACES_FILE'] || File.join(__dir__, 'data', 'places.json')
  FOOD = ['restaurant', 'fast food', 'food truck', 'truck park', 'food hall', 'bakery', 'ice cream', 'cafe'].freeze
  DRINK = ['bar', 'pub', 'beer garden', 'club', 'brewery'].freeze
  VENUE = ['music venue', 'comedy club', 'theater', 'cinema', 'games'].freeze   # places to go out to that aren't food or drink

  # Austin's going-out hot spots: soft glowing zones on the map.
  HOTSPOTS = [
    { id: 'sixth', name: '6th Street', lat: 30.26715, lng: -97.73905, r: 330, vibe: 'Dirty Sixth: bars, clubs and late-night pizza' },
    { id: 'rainey', name: 'Rainey Street', lat: 30.25905, lng: -97.73865, r: 260, vibe: 'bungalow bars and food trucks' },
    { id: 'redriver', name: 'Red River', lat: 30.26860, lng: -97.73585, r: 260, vibe: 'live music venues and dive bars' },
    { id: 'west6', name: 'West 6th', lat: 30.26960, lng: -97.75020, r: 380, vibe: 'cocktail bars and patios' },
    { id: 'soco', name: 'SoCo', lat: 30.24850, lng: -97.75000, r: 520, vibe: 'South Congress: eats, music and people-watching' },
    { id: 'east', name: 'East Austin', lat: 30.26050, lng: -97.72650, r: 650, vibe: 'East 6th and Cesar Chavez: food trucks, breweries, dance spots' },
    { id: 'domain', name: 'The Domain', lat: 30.40150, lng: -97.72480, r: 520, vibe: 'Rock Rose bars, restaurants and rooftops' },
    { id: 'rroldtown', name: 'Old Downtown Round Rock', lat: 30.50850, lng: -97.67830, r: 380, vibe: 'Main Street patios, BBQ and bars' }
  ].freeze

  CATS = {
    'late' => { label: 'Late-night eats', e: '🌙' }, 'early' => { label: 'Early morning', e: '🌅' },
    'bars' => { label: 'Bars', e: '🍸' }, 'clubs' => { label: 'Clubs', e: '🪩' }, 'trucks' => { label: 'Food trucks', e: '🚚' }, 'latetrucks' => { label: 'Late-night food trucks', e: '🚚' }, 'coffee' => { label: 'Coffee', e: '☕' },
    'tacos' => { label: 'Tacos & Tex-Mex', e: '🌮' }, 'bbq' => { label: 'BBQ', e: '🍖' }, 'pizza' => { label: 'Pizza', e: '🍕' },
    'burgers' => { label: 'Burgers', e: '🍔' }, 'asian' => { label: 'Asian', e: '🍜' }, 'sweets' => { label: 'Sweets', e: '🍦' },
    'breweries' => { label: 'Breweries & wineries', e: '🍺' }, 'venues' => { label: 'Venues & shows', e: '🎤' }, 'music' => { label: 'Music venues', e: '🎸' },
    'comedy' => { label: 'Comedy', e: '😂' }, 'theater' => { label: 'Theater', e: '🎭' }, 'cinema' => { label: 'Movies', e: '🎬' },
    'games' => { label: 'Bowling, arcades & billiards', e: '🎳' }, 'speakeasies' => { label: 'Speakeasies & hidden bars', e: '🗝️' },
    'all' => { label: 'Food & drink', e: '🍽️' }
  }.freeze
  CUISINE = {
    'tacos' => /mexican|tex-mex|tex_mex|taco|taqueria|burrito/i, 'bbq' => /barbecue|bbq|smokehouse/i, 'pizza' => /pizza/i,
    'burgers' => /burger/i, 'asian' => /chinese|japanese|thai|vietnamese|korean|sushi|ramen|asian|indian|pho|dumpling/i,
    'sweets' => /ice_cream|ice cream|dessert|donut|doughnut|bakery|cake|frozen_yogurt|gelato|kolache/i, 'coffee' => /coffee/i
  }.freeze

  @cache = { mtime: nil, list: [], fetched: nil }
  @lock = Mutex.new

  module_function

  def data
    mtime = File.mtime(FILE) rescue nil
    @lock.synchronize do
      if mtime != @cache[:mtime]
        raw = mtime ? JSON.parse(File.read(FILE)) : { 'places' => [] }
        list = raw['places'].map { |p| p.merge('week' => Hours.parse(p['hours'])) }
        @cache = { mtime: mtime, list: list, fetched: raw['fetched'] }
        warn "[places] loaded #{list.size} places (#{list.count { |p| p['week'] }} with readable hours)"
      end
      @cache
    end
  end

  def now_mow
    Hours.minute_of_week(Time.now)   # the server runs with TZ=America/Chicago
  end

  def label(st)
    case st[:state]
    when 'open' then st[:always] ? 'Open 24 hours' : "Open till #{Hours.clock(st[:until])}"
    when 'soon' then "Opens at #{Hours.clock(st[:opens])}"
    when 'closed'
      today_left = 1440 - now_mow % 1440
      day = st[:in] <= today_left ? '' : st[:in] <= today_left + 1440 ? ' tomorrow' : " #{%w[Mon Tue Wed Thu Fri Sat Sun][st[:opens] / 1440]}"
      "Closed · opens#{day} #{Hours.clock(st[:opens])}"
    else 'Hours unknown'
    end
  end

  def miles(a_lat, a_lng, b_lat, b_lng)
    r = Math::PI / 180
    h = Math.sin((b_lat - a_lat) * r / 2)**2 + Math.cos(a_lat * r) * Math.cos(b_lat * r) * Math.sin((b_lng - a_lng) * r / 2)**2
    3958.8 * 2 * Math.asin(Math.sqrt(h))
  end

  def zone_of(p)
    HOTSPOTS.find { |z| miles(z[:lat], z[:lng], p['lat'], p['lng']) * 1609.34 <= z[:r] }
  end

  def open_at?(week, mow)
    week && week.any? { |a, b| (a <= mow && mow < b) || (a <= mow + Hours::WEEK && mow + Hours::WEEK < b) }
  end

  def matches?(p, cat, now)
    kind = p['kind']
    text = "#{p['cuisine']&.join(' ')} #{p['name']} #{kind}"
    day = now / 1440 * 1440
    case cat
    when 'late'  # food you can still get at 11:30 tonight
      FOOD.include?(kind) && kind != 'cafe' && open_at?(p['week'], (now % 1440 < 300 ? day - 1440 : day) + 1410)
    when 'early'  # open by 7 AM (today, or tomorrow once the morning has passed)
      (FOOD.include?(kind) || kind == 'cafe') && open_at?(p['week'], (now % 1440 < 600 ? day : day + 1440) % Hours::WEEK + 420)
    when 'bars' then ['bar', 'pub', 'beer garden', 'brewery'].include?(kind)
    when 'breweries' then kind == 'brewery'
    when 'speakeasies' then !!p['speakeasy']
    when 'venues' then VENUE.include?(kind)
    when 'music' then kind == 'music venue'
    when 'comedy' then kind == 'comedy club'
    when 'theater', 'cinema', 'games' then kind == cat
    when 'clubs' then kind == 'club'
    when 'trucks' then ['food truck', 'truck park'].include?(kind)
    when 'latetrucks' then matches?(p, 'trucks', now) && matches?(p, 'late', now)
    when 'coffee' then kind == 'cafe' || text =~ CUISINE['coffee']
    when nil, '', 'all' then true
    else (re = CUISINE[cat]) ? text =~ re || (cat == 'sweets' && %w[bakery ice\ cream].include?(kind)) : true
    end
  end

  RANK = { 'open' => 0, 'soon' => 1, 'unknown' => 2, 'closed' => 3 }.freeze
  # Local first: a Texas chain has to be ~0.5 mi closer, a national chain ~1.5 mi closer, to beat a local spot.
  CHAIN_MILES = { nil => 0, 'texas' => 0.5, 'national' => 1.5 }.freeze

  # q: free text; near: [lat, lng] (rounded, venue-level); zone: hotspot id; open_only: drop closed/unknown
  def search(cat: nil, q: nil, near: nil, zone: nil, open_only: false, limit: 40)
    now = now_mow
    z = HOTSPOTS.find { |h| h[:id] == zone }
    words = q.to_s.downcase.scan(/[a-z0-9']+/) - %w[the a an and or near me open now right tonight in at any some food place places spot spots find show]
    list = data[:list].select do |p|
      next false if z && miles(z[:lat], z[:lng], p['lat'], p['lng']) * 1609.34 > z[:r]
      next false unless matches?(p, cat, now)
      next true if words.empty?
      hay = "#{p['name']} #{p['kind']} #{p['cuisine']&.join(' ')}".downcase
      words.any? { |w| hay.include?(w) || (CUISINE[w] && hay =~ CUISINE[w]) }
    end
    rows = list.map do |p|
      st = Hours.status(p['week'], now)
      d = near ? miles(near[0], near[1], p['lat'], p['lng']) : nil
      { p: p, st: st, mi: d }
    end
    rows.reject! { |r| r[:st][:state] != 'open' } if open_only
    rows.sort_by! { |r| [RANK[r[:st][:state]], (r[:mi] || 0) + CHAIN_MILES.fetch(r[:p]['chain'], 0), r[:p]['name']] }
    rows.first(limit).map { |r| row(r[:p], r[:st], r[:mi]) }
  end

  # The best-known spots in an area ("a good spot in Hyde Park"): inside radius km of the centre, most popular first
  # (popular.json), local places ahead of national chains, open ones a little ahead. `known` is the 0-100 score.
  def best_in(lat, lng, km, cat: nil, open_only: false, limit: 15)
    now = now_mow
    rows = data[:list].select { |p| miles(lat, lng, p['lat'], p['lng']) * 1.609 <= km && matches?(p, cat, now) }.map do |p|
      st = Hours.status(p['week'], now)
      next if open_only && st[:state] != 'open'
      known = Popular[p['id']]
      { p: p, st: st, known: known, rank: known - (p['chain'] == 'national' ? 40 : p['chain'] == 'texas' ? 8 : 0) + (st[:state] == 'open' ? 6 : 0) }
    end.compact
    rows.sort_by { |r| [-r[:rank], r[:p]['name']] }.first(limit).map { |r| row(r[:p], r[:st]).merge(known: r[:known]) }
  end

  def row(p, st = Hours.status(p['week'], now_mow), mi = nil)
    zone = zone_of(p)
    { id: p['id'], name: p['name'], kind: p['kind'], cuisine: p['cuisine'] || [], addr: p['addr'], lat: p['lat'], lng: p['lng'],
      web: p['web'], menu: p['menu'], phone: p['phone'], state: st[:state], status: label(st), closes: st[:state] == 'open' && !st[:always] ? Hours.clock(st[:until]) : nil,
      mi: mi && mi.round(1), zone: zone && zone[:name], chain: p['chain'], alcohol: p['alcohol'], ig: p['ig'], src: p['src'], speakeasy: p['speakeasy'] }.compact
  end

  # Everything, compact, for the map dots (the app works out open/closed itself from `w`).
  # Built once per places file / popularity scores (~10,000 places took ~0.35 s a request, blocking others meanwhile).
  def for_map
    d = data
    key = [d[:mtime], Popular.scores.object_id]
    @map_cache = nil unless @map_cache && @map_cache[0] == key
    (@map_cache ||= [key, { fetched: d[:fetched], places: d[:list].map { |p| [p['id'], p['name'], p['kind'], p['lat'], p['lng'], p['week'], Popular[p['id']]] } }])[1]
  end

  def hotspots
    now = now_mow
    HOTSPOTS.map do |z|
      inside = data[:list].select { |p| miles(z[:lat], z[:lng], p['lat'], p['lng']) * 1609.34 <= z[:r] }
      z.merge(total: inside.size, open: inside.count { |p| Hours.status(p['week'], now)[:state] == 'open' })
    end
  end

  def find(id)
    data[:list].find { |p| p['id'] == id }
  end

  LAST_CALL = 120   # 2 AM: Texas bars stop serving, so it's when a bar or club with unknown hours lets out
  WALK_MI = 0.5     # about a 10-minute walk

  # "This club lets out at 2 AM: what food is still open within walking distance?"
  # From a place id, or from a spot (an event's venue) plus the minute of the week it ends.
  def after(id: nil, lat: nil, lng: nil, ends: nil, limit: 20)
    now = now_mow
    venue = id && find(id)
    return nil if id && !venue
    lat, lng = venue['lat'], venue['lng'] if venue
    assumed = false
    t =
      if ends then ends
      elsif venue && (st = Hours.status(venue['week'], now))[:state] == 'open' && !st[:always] then now + st[:in]
      elsif venue && st[:state] != 'unknown' && !st[:always]   # closed now: when it closes after it next opens
        o = now + st[:in]
        o + Hours.status(venue['week'], o % Hours::WEEK)[:in].to_i
      else   # unknown hours (or open 24 hours): the next 2 AM
        assumed = true
        day = now / 1440 * 1440
        now % 1440 < LAST_CALL ? day + LAST_CALL : day + 1440 + LAST_CALL
      end
    t %= Hours::WEEK
    rows = data[:list].map do |p|
      next if p['id'] == id || !FOOD.include?(p['kind']) || p['kind'] == 'cafe'
      mi = miles(lat, lng, p['lat'], p['lng'])
      next if mi > WALK_MI
      st = Hours.status(p['week'], t)
      next if st[:state] == 'closed' || st[:state] == 'soon'
      next if st[:state] == 'open' && !st[:always] && st[:in] < 20   # closing as you walk up
      { p: p, st: st, mi: mi }
    end.compact
    truck = ->(p) { ['food truck', 'truck park'].include?(p['kind']) ? 0 : 1 }
    rows.sort_by! { |r| [r[:st][:state] == 'open' ? 0 : 1, r[:mi] + CHAIN_MILES.fetch(r[:p]['chain'], 0) / 5 - (truck.(r[:p]).zero? ? 0.1 : 0), r[:p]['name']] }
    rows = rows.uniq { |r| r[:p]["name"].downcase }   # the same spot mapped twice
    open, unknown = rows.partition { |r| r[:st][:state] == 'open' }
    list = (open.first(limit) + unknown.select { |r| truck.(r[:p]).zero? }.first(4)).map do |r|
      row(r[:p], Hours.status(r[:p]['week'], now), r[:mi]).merge(
        walk: [(r[:mi] * 20).round, 1].max, at_close: r[:st][:state] == 'open' ? (r[:st][:always] ? '24 hours' : "till #{Hours.clock(r[:st][:until])}") : 'hours unknown')
    end
    { venue: venue && row(venue), ends: Hours.clock(t), assumed: assumed, places: list }
  end
end
