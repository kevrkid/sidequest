# What the menus we've read are good for beyond one restaurant's sheet: finding a dish anywhere ("birria tacos under
# $5 open now") and happy hours (when, and the deals), both read from data/menus/*.json. MenuIndex keeps one entry
# per menu file and re-reads only the files that changed (checked at most every 30 s).
# Needs from menus.rb: MENU_DIR, menu_cached, menu_keep, menu_slot, MENU_LINES, menu_lines, MENU_SYSTEM, MENU_MODEL.
module MenuIndex
  @lock = Mutex.new
  @files = {}   # path => [mtime, dishes, happy]
  @at = 0

  module_function

  def fold(s)
    s.to_s.dup.force_encoding('UTF-8').scrub('').unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9$.]+/, ' ').strip
  end

  def price_num(p)
    (m = p.to_s.match(/\$?\s*(\d{1,3}(?:\.\d{1,2})?)/)) ? m[1].to_f : nil
  end

  def load
    @lock.synchronize do
      return if Time.now.to_f - @at < 30
      seen = {}
      Dir.glob(File.join(MENU_DIR, '*.json')).each do |f|
        id = File.basename(f, '.json')
        next if id.start_with?('_')
        seen[f] = true
        mt = File.mtime(f).to_f
        next if @files[f] && @files[f][0] == mt
        m = (JSON.parse(File.read(f)) rescue nil)
        dishes = []
        Array(m && m['sections']).each do |s|
          Array(s['items']).each do |i|
            dishes << [id, s['name'].to_s, i['name'].to_s, i['price'], i['desc'], fold("#{i['name']} #{i['desc']} #{s['name']}"), fold(i['name']), price_num(i['price'])]
          end
        end
        h = m && m['happy']
        week = h && Hours.parse(h['hours'])
        @files[f] = [mt, dishes, week ? h.merge('week' => week, 'id' => id) : nil]
      end
      @files.select! { |f, _| seen[f] }
      @at = Time.now.to_f
    end
  end

  def all_dishes
    load
    @lock.synchronize { @files.values.flat_map { |x| x[1] } }
  end

  def all_happy
    load
    @lock.synchronize { @files.values.map(&:last).compact }
  end

  STOP = %w[where can i get find the a an any some best good great near me nearby around here in at for with and or of to who has have
            serves serve sells sell eat buy want looking spot spots place places food austin open now tonight today cheap cheapest under
            less than below dollars dollar bucks price prices is are what whats there that this].freeze

  # "birria tacos under $5 open now" → words ["birria", "taco"], max 5.0, open_only
  def parse(q)
    s = q.to_s.dup.force_encoding('UTF-8').scrub('').downcase   # web queries arrive as bytes
    max = (m = s.match(/(?:under|less than|below|<)\s*\$?\s*(\d{1,3}(?:\.\d\d)?)/)) ? m[1].to_f : nil
    words = fold(s.gsub(/(?:under|less than|below)\s*\$?\s*\d+(?:\.\d\d)?/, ' ')).split.reject { |w| STOP.include?(w) || w =~ /\A\$?\d/ }
    words = words.map { |w| w.size > 3 ? w.sub(/(?<=[^s])s\z/, '') : w }.uniq.first(5)
    [words, max, s =~ /\bopen\b/ ? true : false]
  end

  # Dishes matching every word, best first: the word in the dish's own name, open now, close by. Two per place at most.
  def dishes(q, near: nil, limit: 40)
    words, max, open_only = parse(q)
    return { words: words, results: [] } if words.empty?
    now = Places.now_mow
    per = Hash.new(0)
    hits = all_dishes.select { |d| words.all? { |w| d[5].include?(w) } }.map do |d|
      next if max && (d[7].nil? || d[7] > max)
      p = Places.find(d[0]) or next
      st = Hours.status(p['week'], now)
      next if open_only && st[:state] != 'open'
      mi = near && Places.miles(near[0], near[1], p['lat'], p['lng'])
      score = (words.all? { |w| d[6].include?(w) } ? 4 : 0) + { 'open' => 2, 'soon' => 1, 'unknown' => 0.5 }.fetch(st[:state], 0) -
              (mi || 3) * 0.35 + (d[7] ? 0.5 : 0)
      [score, d, p, st, mi]
    end.compact.sort_by { |s, *| -s }
    rows = hits.select { |_, d| (per[d[0]] += 1) <= 2 }.first(limit).map do |_, d, p, st, mi|
      Places.row(p, st, mi).merge(dish: { name: d[2], price: d[3], desc: d[4].to_s[0, 160], section: d[1] }.compact)
    end
    { words: words, max: max, open: open_only, results: rows }
  end

  # Happy hours: on now first (nearest first), then the ones starting in the next 3 hours, then the rest.
  def happy(near: nil, limit: 80)
    now = Places.now_mow
    rows = all_happy.map do |h|
      p = Places.find(h['id']) or next
      st = Hours.status(h['week'], now)
      mi = near && Places.miles(near[0], near[1], p['lat'], p['lng'])
      on = st[:state] == 'open'
      soon = !on && st[:in].to_i <= 180
      label = on ? (st[:always] ? 'Happy hour all day' : "Happy hour till #{Hours.clock(st[:until])}") : st[:in].to_i < 1440 - now % 1440 ? "Happy hour today at #{Hours.clock(st[:opens])}" :
              "Happy hour #{%w[Mon Tue Wed Thu Fri Sat Sun][st[:opens].to_i / 1440]} #{Hours.clock(st[:opens])}"
      [[on ? 0 : soon ? 1 : 2, mi || 0, st[:in].to_i], Places.row(p, Hours.status(p['week'], now), mi)
        .merge(happy: { now: on, soon: soon, label: label, deals: h['deals'].to_s[0, 160], hours: h['hours'] })]
    end.compact.sort_by(&:first).map(&:last)
    { now: rows.count { |r| r[:happy][:now] }, results: rows.first(limit) }
  end
end

def happy_clean(h)
  return nil unless h.is_a?(Hash) && Hours.parse(h['hours'].to_s)
  { 'hours' => h['hours'].to_s.strip[0, 120], 'deals' => h['deals'].to_s.strip[0, 160] }
end

# Menus read before happy hours were picked out: a quick look at their happy-hour sections (no web, no Google).
def happy_backfill(id, m)
  part = m['sections'].to_a.select { |s| "#{s['name']} #{s['items'].to_a.map { |i| "#{i['name']} #{i['desc']}" }.join(' ')}" =~ /happy\s*hour/i }
  return {} if part.empty? && m['note'].to_s !~ /happy\s*hour/i
  text = (part.map { |s| "## #{s['name']}\n" + s['items'].map { |i| "#{i['name']} | #{i['price']} | #{i['desc']}" }.join("\n") } + [m['note'].to_s]).join("\n")[0, 6000]
  out, = menu_slot do
    run_claude("Here is part of a restaurant's menu. Give only its HAPPY line (or NONE if it doesn't say when happy hour is).\n" + MENU_LINES + "\n" + text,
               nil, system: MENU_SYSTEM, model: MENU_MODEL, effort: 'low', timeout: 45)
  end
  happy_clean(menu_lines(out)['happy']) || {}
rescue => e
  warn "[menu] happy hour for #{id}: #{e.message[0, 80]}"
  nil
end

def mount_menu_finds(server)
  # A dish anywhere: q = "birria tacos", "espresso martini under $14", "open now" works too.
  route(server, '/api/dishes', auth: false, get: true) do |_b, _h, req|
    limit!("dishes:#{client_ip(req)}", 240, 3600)
    lat, lng = req.query['lat'].to_f, req.query['lng'].to_f
    near = lat.between?(29, 32) && lng.between?(-99, -96) ? [lat, lng] : nil
    MenuIndex.dishes(req.query['q'].to_s[0, 80], near: near)
  end
  route(server, '/api/places/happy', auth: false, get: true) do |_b, _h, req|
    limit!("happy:#{client_ip(req)}", 240, 3600)
    lat, lng = req.query['lat'].to_f, req.query['lng'].to_f
    MenuIndex.happy(near: lat.between?(29, 32) && lng.between?(-99, -96) ? [lat, lng] : nil)
  end
end
