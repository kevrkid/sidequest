# Lifestyle: how active, outdoorsy, indoorsy, sporty, night-owl, foodie, arty and exploring someone is, plus how much
# they go to bars, worked out from what they do in Side Quest. It sits beside Personality (the 16 types) but is its own
# score. The phone blends this with their own answers (About you: how active, drinking, cannabis, diet…), so a new
# person starts from what they said and the chart moves as they go out.
#   GET /api/lifestyle  → { traits: { key => { a: 0-100, n: evidence, why: [names] } }, past: [{ at, a, total }], total }
#   total = how many things you've done (recent ones count fully, older ones fade), which sets how much they outweigh your answers
# Only for that person; nothing here is shown to anyone else. Cannabis and diet are never guessed from activity.
LIFESTYLE_TRAITS = %w[active fan outdoors indoor night foodie culture explorer drink].freeze
LIFESTYLE_HALF = 60 * 86_400_000.0   # older things count half as much every two months (like Scout's taste)
LIFESTYLE_K = 6.0                    # points for ~63%: two events gone to, or two check-ins
LIFESTYLE_W = { 'going' => 3.0, 'checkin' => 3.0, 'save' => 2.0, 'interested' => 1.5, 'rate' => 1.0 }.freeze

LS_ACTIVE_RE = /\b(run|runs|running|5k|10k|half marathon|yoga|pilates|cycl|bike ride|group ride|climb|boulder|pickleball|volleyball|kickball|soccer|basketball|hockey|skate|swim|workout|bootcamp|crossfit|disc golf|ultimate|tennis|paddle)/i
LS_OUT_RE = /\b(hike|hiking|trail|kayak|paddle|camp|stargaz|nature|garden|greenbelt|lake|river|park)\b/i
LS_INDOOR_RE = /\b(trivia|bingo|board games?|game night|chess|d&d|dungeons|magic: the gathering|mtg|arcade|bowling|billiards|pool tournament|darts|esports|video games?|karaoke|puzzle)\b/i
LS_DRINK_RE = /\b(beer|brew|ipa|wine|cocktail|whiskey|tequila|mezcal|happy hour|pub crawl|bar crawl|tasting)\b/i
LS_SPORTS_BAR = /\bsports? (bar|pub|grill|lounge)\b|\bwatch party\b/i

# What one thing counts toward: { trait => share } (1.0 = a full point at that thing's weight)
# Events use the category saved with them (they leave the events list once they're over), else today's list.
def lifestyle_tags(k, id, name, tags = [], cat = nil)
  t = Hash.new(0.0)
  case k
  when 'event'
    cat ||= ((EV_INDEX[:by] || {})[id.to_s.sub(/\Ae:/, '')] || {})['category']
    cat = cat.to_s
    text = name.to_s
    case cat
    when 'pickup' then t['active'] += 1
    when 'sports' then t['fan'] += 1
    when 'outdoors' then t['outdoors'] += 1
    when 'games' then t['indoor'] += 1
    when 'nightlife' then t['night'] += 1; t['drink'] += 0.5
    when 'live_music' then t['night'] += 0.5; t['culture'] += 0.5
    when 'food_drink' then t['foodie'] += 1
    when 'theater', 'arts', 'film', 'comedy', 'festival' then t['culture'] += 1
    end
    t['active'] += 0.7 if text =~ LS_ACTIVE_RE && cat != 'pickup'
    t['outdoors'] += 0.5 if text =~ LS_OUT_RE && cat != 'outdoors'
    t['indoor'] += 0.7 if text =~ LS_INDOOR_RE && cat != 'games'
    t['drink'] += 0.7 if text =~ LS_DRINK_RE
    t['fan'] += 0.7 if text =~ LS_SPORTS_BAR && cat != 'sports'
  when 'place'
    p = Places.find(id) or return t
    case p['kind'].to_s
    when 'bar', 'pub' then t['drink'] += 1; t['night'] += 0.5
    when 'beer garden', 'brewery' then t['drink'] += 1
    when 'club' then t['night'] += 1; t['drink'] += 0.7
    when 'games' then t['indoor'] += 1
    when 'cinema' then t['culture'] += 0.7; t['indoor'] += 0.5
    when 'theater', 'comedy club' then t['culture'] += 1
    when 'music venue' then t['night'] += 0.7; t['culture'] += 0.5
    else t['foodie'] += 1
    end
    t['fan'] += 0.8 if p['name'].to_s =~ LS_SPORTS_BAR
    t['indoor'] += 0.5 if p['name'].to_s =~ /billiard|pool hall|arcade|bowl|board game|barcade/i && p['kind'] != 'games'
  when 'gym'
    t['active'] += 1
  when 'area'
    t['outdoors'] += 1
  when 'sight'
    s = Sights.find(id)
    kind = s ? s['kind'].to_s : ''
    %w[nature view].include?(kind) ? t['outdoors'] += 1 : t['culture'] += 0.7
  end
  t['night'] += 0.7 if tags.include?('late')
  t
end

# Every point, with when it happened: going / interested / saves from Scout's taste list (check-ins come from the
# check-in log instead, which also has gyms and parks), check-ins, and food ratings.
def lifestyle_points(d, h)
  pts = []
  ((d['taste'] || {})[h] || []).each do |x|
    next if x['how'] == 'checkin'   # counted from the check-in log below (it has gyms, parks and the late tag)
    pts << { k: x['k'], id: x['id'], name: x['name'].to_s, how: x['how'], at: x['at'].to_i, food: x['food'], cat: x['cat'] }
  end
  (((d['quest'] || {})[h] || {})['checkins'] || []).each do |c|
    pts << { k: c['k'], id: c['id'], name: c['name'].to_s, how: 'checkin', at: c['at'].to_i, tags: c['tags'] || [], zone: c['zone'] }
  end
  (d['ratings'] || {}).each do |id, by|
    r = by[h] or next
    pts << { k: 'rate', id: id, name: '', how: 'rate', at: r['at'].to_i }
  end
  pts
end

# Done outside the store lock: place / sight lookups and the event categories
def lifestyle_tag_all!(pts)
  pts.each do |pt|
    if pt[:k] == 'rate'
      pt[:name] = (Places.find(pt[:id]) || {})['name'].to_s
      pt[:t] = { 'foodie' => 1.0 }
    else
      pt[:t] = lifestyle_tags(pt[:k], pt[:id], pt[:name], pt[:tags] || [], pt[:cat])
    end
  end
end

# Scores as of time `asof` (ms): each trait's decayed points → 0-100, with what counted most.
def lifestyle_scores(pts, asof)
  sum = Hash.new(0.0); why = Hash.new { |x, k| x[k] = Hash.new(0.0) }
  places = {}; zones = {}; cuisines = {}; count = 0
  pts.each do |pt|
    next if pt[:at] > asof || pt[:at] <= 0
    count += 0.5**((asof - pt[:at]) / LIFESTYLE_HALF)
    w = LIFESTYLE_W[pt[:how]].to_f * 0.5**((asof - pt[:at]) / LIFESTYLE_HALF)
    pt[:t].each do |tr, share|
      sum[tr] += w * share
      why[tr][pt[:name]] += w * share unless pt[:name].empty?
    end
    if pt[:how] == 'checkin' && asof - pt[:at] < 90 * 86_400_000
      places["#{pt[:k]}:#{pt[:id]}"] = pt[:name]
      zones[pt[:zone]] = true if pt[:zone]
    end
    cuisines[pt[:food].to_s.downcase] = true if pt[:food] && !pt[:food].to_s.empty? && pt[:at] > asof - 180 * 86_400_000
  end
  sum['explorer'] += places.size * 1.5 + zones.size * 2
  why['explorer'] = places.values.last(3).each_with_object({}) { |n, o| o[n] = 1 }
  sum['foodie'] += [cuisines.size - 1, 0].max * 0.8
  traits = LIFESTYLE_TRAITS.each_with_object({}) do |tr, o|
    o[tr] = { a: (100 * (1 - Math.exp(-sum[tr] / LIFESTYLE_K))).round, n: sum[tr].round(1),
              why: why[tr].sort_by { |_, v| -v }.first(3).map(&:first) }
  end
  [traits, count.round(1)]
end

def mount_lifestyle(server)
  route(server, '/api/lifestyle', get: true) do |_b, h|
    event_by_uid('')   # refresh the events index before taking the lock (it may call the events service)
    pts = lifestyle_tag_all!(store(write: false) { |d| lifestyle_points(d, h) })
    now = now_ms
    traits, total = lifestyle_scores(pts, now)
    past = [84, 56, 28, 14, 7].map do |days|   # the weeks before, for the chart's "a month ago" outline and the trend
      at = now - days * 86_400_000
      tr, tot = lifestyle_scores(pts, at)
      { at: at, a: tr.transform_values { |v| v[:a] }, total: tot }
    end
    { traits: traits, past: past, total: total }
  end
end
