# Events whose spot the scraper couldn't find get dropped on the middle of their city (all of Austin's land on one
# downtown corner: a pickup game "at Lakeline Park" showed up on Congress Avenue). Before the app sees them, look for
# the real spot: the venue or a park / landmark named in the title, from our own map data (parks, sights, places),
# then OpenStreetMap's free geocoder for what's left (once per venue, 1 request a second, cached in data/geofix.json).
# Events still without a spot are marked so the map leaves them off instead of guessing.
require 'json'
require 'net/http'
require 'uri'

module Geofix
  DATA = File.join(__dir__, 'data')
  CACHE_FILE = File.join(DATA, 'geofix.json')
  BOX = [29.75, -98.25, 30.75, -97.30]   # San Marcos to Georgetown, Lake Travis to Manor: where our events are
  # Venue names the scrapers use → the name in our map data
  ALIASES = { 'acl live at the moody theater' => 'moody theater', 'acl live at 3ten' => 'moody theater', 'acl live' => 'moody theater',
              'dkr texas memorial stadium' => 'darrell k royal texas memorial stadium', 'circuit of the americas cota' => 'circuit of the americas',
              'strahan arena at the university events center' => 'strahan arena' }.freeze
  # Big venues the scrapers name without an address, which the geocoder can't find by name
  VENUE_ADDR = { 'cap city comedy club' => '8120 Research Blvd, Austin, TX 78758' }.freeze
  NOT_A_PLACE = /\A(none|tba|tbd|online|virtual|details in description|my home|private|.*\$\d)/i

  @index = nil; @cache = nil; @queue = []; @lock = Mutex.new; @worker = nil

  module_function

  def norm(s) s.to_s.downcase.gsub(/&/, ' and ').gsub(/[’']/, '').gsub(/\(.*?\)/, ' ').gsub(/[^a-z0-9]+/, ' ').sub(/\Athe /, '').strip end
  def in_box?(la, ln) la.to_f.between?(BOX[0], BOX[2]) && ln.to_f.between?(BOX[1], BOX[3]) end

  # name → [lat, lng] from parks / lakes (outdoors.json), sights and food & drink places. A name used for two spots
  # far apart (two "Central Park"s) is left out: better no pin than the wrong one.
  def index
    @index ||= begin
      spots = {}
      add = lambda do |name, lat, lng, text_ok, part_ok = true|
        n = norm(name); next if n.size < 4 || !in_box?(lat, lng)
        if (o = spots[n]) && ((o[0] - lat).abs + (o[1] - lng).abs) > 0.01 then o[3] = true   # ambiguous
        else spots[n] ||= [lat.to_f, lng.to_f, text_ok, false, part_ok] end
      end
      load = ->(f) { JSON.parse(File.read(File.join(DATA, f))) rescue nil }
      (load.('outdoors.json')&.dig('areas') || []).each { |a| add.(a['name'], a['c'][0], a['c'][1], true) if a['name'] && a['kind'] != 'trail' && a['kind'] != 'river' }
      (load.('sights.json')&.dig('sights') || []).each { |s| add.(s['name'], s['lat'], s['lng'], s['kind'] != 'marker') }
      # "Garage" is a bar, and chains have branches all over: places only by their exact name in the venue field
      (load.('places.json')&.dig('places') || []).each { |p| add.(p['name'], p['lat'], p['lng'], false, false) }
      spots.reject { |_, v| v[3] }
    end
  end

  def cache
    @cache ||= (JSON.parse(File.read(CACHE_FILE)) rescue {})
  end

  # Where this event really is, or nil
  def locate(e)
    venue = norm(e['venue'])
    venue = ALIASES.find { |k, _| venue == k || venue.start_with?("#{k} ") }&.last || venue
    unless venue.empty? || e['venue'].to_s =~ NOT_A_PLACE
      hit = index[venue] || index.find { |n, v| v[4] && n.size >= 8 && (venue.start_with?("#{n} ") || venue.end_with?(" #{n}")) }&.last
      return [hit[0], hit[1], 'venue'] if hit
    end
    # A park or landmark named in the title ("10v10 pickup game - Lakeline Park"): whole words, longest name first
    title = " #{norm(e['title'])} "
    name, hit = index.select { |n, v| v[2] && n.size >= 10 && title.include?(" #{n} ") }.max_by { |n, _| n.size }
    return [hit[0], hit[1], 'title'] if hit
    # The geocoder, for venues and street addresses we don't have
    q = geocode_query(e)
    if q && (c = cache[q])
      return c['lat'] ? [c['lat'], c['lng'], 'geocoder'] : nil
    end
    enqueue(q) if q
    nil
  end

  def geocode_query(e)
    v = e['venue'].to_s.strip.sub(/\A(near|by|behind|outside|at) (the )?/i, '')
    a = e['address'].to_s.strip
    return nil if v.empty? && a.empty?
    return nil if v =~ NOT_A_PLACE && a.empty?
    return VENUE_ADDR[norm(v)] if VENUE_ADDR[norm(v)]
    q = if a =~ /\A\d+ \S/ then clean_address(a)   # a street address beats a name
        elsif v =~ /\A\d+ \S/ then clean_address(v)
        else "#{v}, #{e['city'].to_s =~ /\A[A-Za-z .]{3,30}\z/ && e['city'] !~ /details/i ? e['city'] : 'Austin'}, TX" end
    q[0, 140]
  end

  ORDINALS = %w[first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth].each_with_index
                                                                                                      .to_h { |w, i| [w, "#{i + 1}#{i.zero? ? 'st' : i == 1 ? 'nd' : i == 2 ? 'rd' : 'th'}"] }
  # "701 Tillery Street #Suite C Austin, TX 78702 United States" → "701 Tillery Street, Austin, TX 78702"
  def clean_address(a)
    a = a.gsub(/\s*(#\s*)?\b(suite|ste|unit|bldg|building|apt)\b\.?\s*[\w-]+/i, ',').gsub(/\s*#\s*[\w-]+/, ',')
         .gsub(/\b(USA|United States)\b/i, '').sub(/\A(\d+)-\d+ /, '\\1 ')
         .gsub(/\b(#{ORDINALS.keys.join('|')})\b/i) { ORDINALS[$1.downcase] }
    parts = a.split(',').map(&:strip).reject(&:empty?).uniq { |p| p.downcase }.reject.with_index { |p, i| i.positive? && p =~ /\A(TX|Texas)\z/i && a.scan(/\b(TX|Texas)\b/i).size > 1 }
    parts.join(', ')
  end

  GENERIC = %w[austin texas center club the and park field room house north south east west street suite city bar]
  # Only an answer that's plainly the place we asked for: same house number and street, or a shared real word in the name
  def plausible?(q, r)
    ad = r['address'] || {}
    if (num = q[/\A(\d+) /, 1])
      street = q[/\A\d+ ([^,]+)/, 1].to_s.downcase.split.reject { |w| w.size < 3 || %w[street st ave avenue blvd rd road dr drive ln lane way].include?(w) }
      ad['house_number'].to_s.split(/[;,-]/).map(&:strip).include?(num) && street.any? { |w| ad['road'].to_s.downcase.include?(w) }
    else
      want = norm(q.split(',').first).split - GENERIC
      got = norm("#{r['name']} #{r['display_name'].to_s.split(',').first}").split
      want.any? { |w| w.size >= 4 && got.include?(w) }
    end
  end

  def enqueue(q)
    @lock.synchronize do
      return if @queue.include?(q) || cache.key?(q)
      @queue << q
      @worker = nil unless @worker&.alive?
      @worker ||= Thread.new { work }
    end
  end

  def work
    loop do
      q = @lock.synchronize { @queue.shift }
      break unless q
      sleep 1.1   # OpenStreetMap's rule: at most one request a second
      res = begin
        uri = URI("https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(q: q, format: 'json', limit: 3, countrycodes: 'us', addressdetails: 1,
                                                                                    viewbox: "#{BOX[1]},#{BOX[2]},#{BOX[3]},#{BOX[0]}", bounded: 1)}")
        r = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (event venue lookup)') }
        r.code == '200' ? JSON.parse(r.body).find { |x| plausible?(q, x) } : :retry
      rescue StandardError
        :retry
      end
      next if res == :retry   # try again on the next refresh
      @lock.synchronize do
        cache[q] = res && in_box?(res['lat'], res['lon']) ? { 'lat' => res['lat'].to_f.round(6), 'lng' => res['lon'].to_f.round(6) } : {}
        File.write(CACHE_FILE, JSON.generate(cache))
      end
    end
  end

  # The events service's JSON, with spots filled in where we can and `geo_none` where we can't.
  def fix_body(body)
    j = JSON.parse(body)
    list = j.is_a?(Hash) ? j['events'] : j
    return body unless list.is_a?(Array)
    list.each do |e|
      next if e['geo_precise'] && e['lat'].to_f != 0
      if (spot = locate(e))
        e['lat'], e['lng'] = spot[0].round(6), spot[1].round(6)
        e['geo_precise'] = true; e['geo_fixed'] = spot[2]
      else
        e['geo_none'] = true   # city-level guess: lists show it, the map doesn't
      end
    end
    JSON.generate(j)
  rescue JSON::ParserError
    body
  end
end
