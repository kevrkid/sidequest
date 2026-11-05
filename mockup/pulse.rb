# frozen_string_literal: true

# Pulse: what's actually happening at places right now, what it'll be like later, and the one right
# place for you tonight, so people pick well once instead of bar hopping.
#
#   heat      every check-in, vibe report, story, post, flare and live stream at a place adds heat that
#             fades (each kind has its own half-life). One person counts once per place (their strongest
#             signal + a little for the rest), so one account can't fake a crowd.
#   forecast  168 hourly bins (Mon 0 AM .. Sun 11 PM) per place: a prior from what kind of place it is
#             (bars peak 10 PM-12 AM, Fri/Sat; cafés 9 AM; restaurants lunch + dinner), masked by its real
#             opening hours and scaled by how well known it is, blended with what Side Quest has seen
#             there (data/pulse.json, folded every hour, older weeks fade).
#   vibe      busy level now = forecast for this hour, pulled toward live heat and people's own reports
#             (💤 dead · 😌 chill · 🔥 lively · 🚫 packed), plus words from captions and reports (DJ,
#             line, patio...). Comes with how sure we are and the freshest photo/video/stream as proof.
#   facts     today's hours, last call, busiest window, best time to get there, how long it stays good.
#   trends    places busier than usual for this hour (heat vs forecast), zones, events gaining RSVPs.
#   pick      ranks places for one person over their whole night (taste, wanted vibe, friends there,
#             whether it stays good and open for the window, distance), with reasons and a Plan B
#             a short walk away.
#   feed      stories, posts and live streams ranked by freshness, engagement, how hot the place is,
#             friends, taste and distance, with no author or place repeating too often.
#
# Everything is "usually" until Side Quest has seen a place; the app says so.
require 'json'
require 'fileutils'

module Pulse
  FILE = ENV['SQ_PULSE_FILE'] || File.join(__dir__, 'data', 'pulse.json')
  WEEK_H = 168
  # weight, half-life in minutes
  KINDS = { 'vibe' => [4.0, 45], 'checkin' => [3.0, 75], 'live' => [5.0, 20], 'story' => [2.0, 60],
            'flare' => [2.5, 60], 'post' => [1.5, 120] }.freeze
  LEVELS = [[0.2, 'quiet', '💤', 'Quiet'], [0.45, 'chill', '😌', 'Chill'], [0.7, 'lively', '🔥', 'Lively'],
            [0.86, 'busy', '🎉', 'Busy'], [9, 'packed', '🚫', 'Packed']].freeze
  REPORT = { 'dead' => 0.08, 'chill' => 0.35, 'lively' => 0.65, 'packed' => 0.95 }.freeze
  WANT = { 'chill' => 0.35, 'lively' => 0.62, 'party' => 0.85 }.freeze
  REPORT_TAGS = %w[line cover music dj dancing patio sports loud quiet].freeze
  WORDS = { 'line' => /\b(line|wait(ing)?|queue|fila)\b/i, 'cover' => /\bcover( charge)?\b/i,
            'live music' => /\b(live music|band|en vivo)\b/i, 'DJ' => /\bdj\b/i, 'dancing' => /\b(danc\w*|bail\w*)\b/i,
            'patio' => /\b(patio|terraza)\b/i, 'rooftop' => /\b(rooftop|azotea)\b/i, 'karaoke' => /\bkaraoke\b/i,
            'sports on' => /\b(game|match|ufc|nfl|partido)\b/i, 'loud' => /\b(loud|lit|turnt|wild)\b/i,
            'chill' => /\b(chill|cozy|calm|tranquilo)\b/i, 'packed' => /\b(packed|crowded|lleno)\b/i,
            'dead' => /\b(dead|empty|vac[ií]o)\b/i, 'great food' => /\b(delicious|so good|bomb|amazing food)\b/i }.freeze
  NIGHT = %w[bar pub club beer\ garden].freeze

  module_function

  # ---- time ----
  def hour_of_week(t) ((t.wday + 6) % 7) * 24 + t.hour end
  def bin_label(b) "#{%w[Mon Tue Wed Thu Fri Sat Sun][b / 24]} #{clock_h(b % 24)}" end
  def clock_h(h) h.zero? ? '12 AM' : h < 12 ? "#{h} AM" : h == 12 ? '12 PM' : "#{h - 12} PM" end
  def clock_hm(h, m) m.zero? ? clock_h(h) : format('%d:%02d %s', h % 12 == 0 ? 12 : h % 12, m, h < 12 ? 'AM' : 'PM') end

  # ---- forecast prior: what a place like this is usually like, hour by hour ----
  def bump(h, mu, sd) d = [(h - mu).abs, 24 - (h - mu).abs].min; Math.exp(-0.5 * (d / sd)**2) end

  DAY_X = { # Mon..Sun multipliers
    night: [0.45, 0.5, 0.65, 0.85, 1.0, 1.0, 0.55], club: [0.15, 0.2, 0.35, 0.7, 1.0, 1.0, 0.3],
    food: [0.8, 0.8, 0.85, 0.9, 1.0, 1.0, 0.95], cafe: [0.9, 0.9, 0.9, 0.9, 0.95, 1.0, 1.0]
  }.freeze

  # A 0..1 shape over the week for this kind of place (the busiest usual hour = 1).
  def prior_curve(kind)
    raw = Array.new(WEEK_H) do |b|
      day, h = b.divmod(24)
      wkend = day >= 5
      # a bar's Friday night runs past midnight into Saturday: hours before 5 AM belong to the night before
      nd = h < 5 ? (day + 6) % 7 : day
      case kind
      when 'club' then DAY_X[:club][nd] * bump(h, 0.5, 1.6)
      when 'bar', 'pub' then DAY_X[:night][nd] * (bump(h, 23, 2.2) + 0.35 * bump(h, 18, 1.5))
      when 'beer garden', 'brewery' then DAY_X[:night][nd] * (bump(h, 20, 2.5) + (wkend ? 0.6 * bump(h, 15, 2) : 0))
      when 'music venue', 'comedy club', 'theater' then DAY_X[:night][nd] * bump(h, 21, 1.6)   # shows: the evening, Fri/Sat most
      when 'cinema' then DAY_X[:food][day] * (bump(h, 19.5, 2) + (wkend ? 0.5 * bump(h, 14, 2) : 0))
      when 'games' then DAY_X[:night][nd] * (bump(h, 20, 2.5) + (wkend ? 0.5 * bump(h, 15, 2) : 0))
      when 'cafe' then DAY_X[:cafe][day] * (bump(h, 9, 1.6) + 0.35 * bump(h, 14, 2))
      when 'bakery' then DAY_X[:cafe][day] * bump(h, 9, 2)
      when 'ice cream' then DAY_X[:food][day] * bump(h, 19, 2.5)
      when 'food truck', 'truck park'
        DAY_X[:food][day] * (0.7 * bump(h, 12.5, 1.3) + bump(h, 20, 2)) + (h < 3 && [5, 6].include?(day) ? 0.6 * bump(h, 0.5, 1.2) : 0)
      when 'fast food' then DAY_X[:food][day] * (bump(h, 12.5, 1.2) + 0.8 * bump(h, 18.5, 1.5) + 0.3 * bump(h, 0.5, 1.5))
      else # restaurants, food halls, anything else that serves food
        DAY_X[:food][day] * (0.75 * bump(h, 12.5, 1.2) + bump(h, 19, 1.4)) + (wkend ? 0.6 * bump(h, 11, 1.3) : 0)
      end
    end
    top = raw.max.to_f
    raw.map { |x| top.positive? ? x / top : 0 }
  end

  CURVES = Hash.new { |hsh, k| hsh[k] = prior_curve(k) }

  # Is it open during hour-of-week b? `week` is Hours.parse's minute ranges; nil = we don't know.
  def open_in_bin?(week, b)
    return nil unless week
    a = b * 60 + 30   # the middle of the hour
    week.any? { |s, e| (s <= a && a < e) || (s <= a + 10_080 && a + 10_080 < e) }
  end

  # How well known a place is (popular.rb's 0..100, unranked = 40) → 0.35..1
  def fame(pop) (0.35 + 0.65 * ((pop || 40).to_f / 100).clamp(0, 1)).round(3) end

  # Learned history for a place: { 's' => 168 decayed counts } and the city's { 'w' => 168 decayed weeks }.
  def learned_curve(hist, weeks)
    return [nil, 0] unless hist && hist['s']
    rate = hist['s'].each_with_index.map { |x, b| x.to_f / [weeks[b].to_f, 1].max }
    top = rate.max.to_f
    return [nil, 0] unless top.positive?
    [rate.map { |x| x / top }, hist['n'].to_f]
  end

  # The place's forecast, 0..1 per hour of the week (1 ~ as packed as it gets).
  def forecast(place, hist: nil, weeks: nil)
    prior = CURVES[place['kind'].to_s]
    learned, n = learned_curve(hist, weeks || Array.new(WEEK_H, 1))
    wl = n / (n + 25.0)   # 25 people seen there before history counts as much as the prior
    f = fame(place['pop'])
    Array.new(WEEK_H) do |b|
      open = open_in_bin?(place['week'], b)
      next 0.0 if open == false
      shape = learned ? (1 - wl) * prior[b] + wl * learned[b] : prior[b]
      (shape * f).round(3)
    end
  end

  def level_of(x) LEVELS.find { |cut, *_| x < cut } end

  # ---- live heat ----
  # signals: [{ 'k', 'pid', 'at' (ms), 'u', 'v' (report), 'tags', 'text', 'media' }]
  def heat(signals, now_ms)
    by_u = Hash.new { |h, k| h[k] = [] }
    signals.each do |s|
      w, half = KINDS[s['k']] || next
      age = (now_ms - s['at'].to_i) / 60_000.0
      next if age < -0.1 || age > half * 6   # a live stream is stamped a moment after the caller's "now"; the future is ignored
      age = 0 if age.negative?
      by_u[s['u'] || s.object_id] << w * 0.5**(age / half)
    end
    by_u.values.sum { |xs| xs.sort!.reverse!; xs.first + 0.25 * xs.drop(1).sum }.round(3)
  end

  def people(signals) signals.map { |s| s['u'] }.compact.uniq.size end

  # Reports people made there in the last hour, newest counting most: the crowd level they saw, or nil.
  def reported(signals, now_ms)
    rs = signals.select { |s| s['k'] == 'vibe' && REPORT[s['v']] && now_ms - s['at'] < 3_600_000 }
    return nil if rs.empty?
    ws = rs.map { |s| 0.5**((now_ms - s['at']) / 60_000.0 / 25) }
    [rs.zip(ws).sum { |s, w| REPORT[s['v']] * w } / ws.sum, rs.size]
  end

  # Words people used there lately, most-said first.
  def words(signals, now_ms)
    tally = Hash.new(0)
    signals.each do |s|
      next if now_ms - s['at'].to_i > 3 * 3_600_000
      Array(s['tags']).each { |t| tally[{ 'dj' => 'DJ', 'music' => 'live music', 'sports' => 'sports on' }[t] || t] += 2 if REPORT_TAGS.include?(t) }
      WORDS.each { |w, re| tally[w] += 1 if s['text'].to_s =~ re }
    end
    tally.sort_by { |w, n| [-n, w] }.first(4).map(&:first)
  end

  # Heat that means "as packed as the forecast's 1.0": about 8 people in the app there at once.
  FULL_HEAT = 9.0

  # Right now at one place: level, label, how sure, words, proof.
  def vibe(place, signals, now: Time.now, fc: nil)
    now_ms = (now.to_f * 1000).to_i
    fc ||= forecast(place)
    b = hour_of_week(now)
    base = fc[b]
    h = heat(signals, now_ms)
    live_level = 1 - Math.exp(-h / (FULL_HEAT * 0.55))
    seen = people(signals.select { |s| now_ms - s['at'].to_i < 2 * 3_600_000 })
    c_live = 1 - Math.exp(-seen / 3.0)            # 3 people → 63% trust in what the app sees
    level = (1 - c_live) * base + c_live * live_level
    rep = reported(signals, now_ms)
    level = 0.25 * level + 0.75 * rep[0] if rep  # someone standing there beats any model
    open = open_in_bin?(place['week'], b)
    level = 0.0 if open == false && !rep && seen.zero?
    lv = level_of(level)
    sure = rep ? 'high' : seen >= 3 ? 'high' : seen.positive? ? 'some' : 'usual'
    { level: level.round(2), key: lv[1], e: lv[2], label: lv[3], sure: sure, people: seen, reports: rep ? rep[1] : 0,
      heat: h, usual: base, hot: trending?(h, base) ? hotter_than_usual(h, base, now - (now.hour < 5 ? 5 * 3600 : 0)) : nil, words: words(signals, now_ms),
      open: open, at: now_ms }
  end

  def trending?(h, base) h >= 3 && (h + 1) / (base * FULL_HEAT + 1) >= 1.8 end
  def hotter_than_usual(h, base, now = Time.now)
    x = (h + 1) / (base * FULL_HEAT + 1)
    "#{x >= 3 ? 'Way' : 'Much'} busier than a usual #{now.strftime('%A')}#{now.hour < 5 || now.hour >= 17 ? ' night' : ''}"
  end

  # ---- facts & schedule ----
  def facts(place, fc, now: Time.now, learned_n: 0)
    b0 = hour_of_week(now)
    day_bins = (0..23).map { |i| (b0 - now.hour + (now.hour < 5 ? -24 : 0) + 5 + i) % WEEK_H } # 5 AM today → 4 AM tomorrow
    open_bins = day_bins.select { |b| fc[b].positive? }
    out = { based_on: learned_n >= 10 ? "#{learned_n.round} visits seen here" : 'what places like this are usually like' }
    if (st = place['state']) then out[:status] = st end
    out[:last_call] = 'Last call ~1:45 AM' if NIGHT.include?(place['kind']) && closes_at_2?(place['week'], b0)
    return out if open_bins.empty?
    top = open_bins.map { |b| fc[b] }.max
    peak = longest_run(day_bins) { |b| fc[b] >= 0.85 * top }
    out[:peak] = "Busiest #{clock_h(peak.first % 24)}–#{clock_h((peak.last + 1) % 24)}" if peak && top >= 0.3
    if peak
      # the last 3 hours before the peak only: never "get there by 1:30 PM" for a 7 PM rush
      before = day_bins.take_while { |b| b != peak.first }.last(3)
      arrive = before.reverse.find { |b| fc[b].between?(0.3, 0.7 * top) } || before.last
      out[:arrive] = "Get there by #{clock_hm(arrive % 24, 30)} to beat the crowd" if arrive && top >= 0.45 && fc[arrive] < 0.8 * top
    end
    quiet = open_bins.min_by { |b| fc[b] }
    out[:quiet] = "Quietest around #{clock_h(quiet % 24)}" if quiet && fc[quiet] < 0.5 * top
    out[:hours] = day_bins.map { |b| { h: b % 24, v: fc[b] } }
    out
  end

  def closes_at_2?(week, b)
    return true unless week # Texas bars with unknown hours: 2 AM
    week.any? { |_, e| (e % 1440).between?(100, 135) }
  end

  def longest_run(bins)
    best = cur = nil
    bins.each do |b|
      if yield(b) then (cur ||= []) << b; best = cur.dup if !best || cur.size > best.size
      else cur = nil
      end
    end
    best
  end

  # From hour b0 on, how many hours the place stays open and within ±0.25 of the wanted level.
  def stays_good(fc, b0, want, hours)
    (0...hours).take_while { |i| (x = fc[(b0 + i) % WEEK_H]).positive? && (x - want).abs <= 0.25 }.size
  end

  # ---- the right place for one person tonight ----
  # cands: [{ place:, fc:, vibe:, km:, friends: [h], events: [{title, start, fits}], fit: 0..1, media: n }]
  def rank(cands, want: nil, hours: 3, now: Time.now)
    target = WANT[want] || 0.6
    b0 = hour_of_week(now)
    scored = cands.map do |c|
      fc, v = c[:fc], c[:vibe]
      window = (0...hours).map { |i| fc[(b0 + i) % WEEK_H] }
      window[0] = v[:level]   # the first hour is what it's like now, not what it usually is
      fit_w = window.map { |x| x.positive? ? 1 - [((x - target).abs / 0.45), 1].min : 0 }.sum / hours
      stay = c[:stay] = (0...hours).take_while { |i| window[i].positive? && (window[i] - target).abs <= 0.25 }.size
      r = []
      s = 2.5 * fit_w + 1.2 * stay / hours.to_f + 2.0 * c[:fit].to_f
      s += 1.6 * [c[:friends].size, 3].min / 3.0
      s += 0.8 if v[:hot]
      s += 0.6 * fame_bonus(c[:place])
      s += 0.3 if c[:media].to_i.positive?
      s -= 1.1 * Math.log(1 + c[:km].to_f)
      s -= 2.5 if window[0].zero?
      ev = (c[:events] || []).find { |e| e[:fits] } || (c[:events] || []).first
      s += ev[:fits] ? 1.2 : 0.5 if ev
      r << "#{c[:friends].first(2).map { |f| "@#{f}" }.join(', ')} #{c[:friends].size > 1 ? 'are' : 'is'} there" if c[:friends].any?
      r << "#{v[:e]} #{v[:label]} now#{v[:sure] == 'usual' ? ' (usually)' : ''}" if v[:open] != false
      r << v[:hot] if v[:hot]
      r << "#{ev[:title]} #{ev[:when]}" if ev
      r << (stay >= hours ? "Stays #{want ? "#{want} " : ''}good your whole night" : stay >= 2 ? "Good for #{stay} hours" : nil)
      r << 'Your kind of place' if c[:fit].to_f >= 0.5
      mi = c[:km].to_f * 0.621
      r << (mi < 0.1 ? 'Right here' : mi < 0.6 ? "#{(mi * 20).round} min walk" : format('%.1f mi', mi))
      c.merge(score: s.round(3), why: r.compact)
    end
    scored.sort_by { |c| -c[:score] }
  end

  def fame_bonus(place) ((place['pop'] || 40).to_f / 100).clamp(0, 1) end

  # ---- media feed ----
  # items: [{ id:, type: 'story'|'post'|'live', u:, at: ms, likes:, views:, comments:, pid:, km:, friend:, fit: 0..1, heat_x: }]
  def rank_media(items, now_ms)
    seen_u = Hash.new(0); seen_p = Hash.new(0)
    scored = items.map do |m|
      age_h = [(now_ms - m[:at].to_i) / 3_600_000.0, 0].max
      tau = { 'story' => 6, 'post' => 30, 'live' => 1 }[m[:type]] || 12
      fresh = Math.exp(-age_h / tau)
      eng = Math.log(1 + 2 * m[:likes].to_i + 0.2 * m[:views].to_i + 3 * m[:comments].to_i) / (age_h + 2)**0.3
      rel = 1 + 0.9 * [m[:heat_x].to_f, 2].min + 0.6 * m[:fit].to_f + (m[:friend] ? 1.0 : 0) + 0.6 * Math.exp(-m[:km].to_f / 5)
      base = (m[:type] == 'live' ? 3.0 : 1.0) * (0.35 + fresh) * (1 + eng) * rel
      m.merge(raw: base)
    end
    out = []
    pool = scored.sort_by { |m| -m[:raw] }
    until pool.empty?   # greedy: the best one left after the repeat penalty, one at a time
      m = pool.max_by { |x| x[:raw] * 0.55**seen_u[x[:u]] * (x[:pid] ? 0.7**seen_p[x[:pid]] : 1) }
      pool.delete(m)
      seen_u[m[:u]] += 1; seen_p[m[:pid]] += 1 if m[:pid]
      out << m
    end
    out
  end

  # ---- history: data/pulse.json ----
  @lock = Mutex.new
  @db = nil
  def db
    @lock.synchronize do
      @db ||= (JSON.parse(File.read(FILE)) rescue nil) || {}
      @db['w'] ||= Array.new(WEEK_H, 0.0); @db['p'] ||= {}; @db['ev'] ||= {}
      @db
    end
  end

  def save!
    @lock.synchronize do
      FileUtils.mkdir_p(File.dirname(FILE))
      File.write("#{FILE}.tmp", JSON.generate(@db)); File.rename("#{FILE}.tmp", FILE)
    end
  end

  GAMMA = 0.85   # each week of history counts 85% of the week after it

  # Fold one finished hour (bin b) in: people seen at each place that hour.
  def fold!(b, counts)
    d = db
    @lock.synchronize do
      d['w'][b] = d['w'][b].to_f * GAMMA + 1
      ids = d['p'].keys | counts.keys
      ids.each do |pid|
        h = (d['p'][pid] ||= { 's' => Array.new(WEEK_H, 0.0), 'n' => 0.0 })
        c = counts[pid].to_f
        h['s'][b] = (h['s'][b].to_f * GAMMA + c).round(4)
        h['n'] = (h['n'].to_f + c).round(2)
        d['p'].delete(pid) if h['s'].all? { |x| x < 0.01 }
      end
      d['folded'] = b
    end
  end

  # Event RSVP counts over time, to spot the ones taking off.
  def note_events!(counts, now_ms)
    d = db
    @lock.synchronize do
      counts.each { |uid, n| (d['ev'][uid] ||= []) << [now_ms, n] }
      d['ev'].each_value { |xs| xs.reject! { |at, _| at < now_ms - 72 * 3_600_000 } }
      d['ev'].reject! { |_, xs| xs.empty? }
    end
  end

  # Going now minus going ~a day ago (or when we first saw it, if that's 2+ hours back). Never seen before = 0.
  def event_growth(uid, n_now, now_ms)
    xs = db['ev'][uid] || []
    base = xs.select { |at, _| at <= now_ms - 20 * 3_600_000 }.last || xs.find { |at, _| at <= now_ms - 2 * 3_600_000 }
    base ? n_now - base[1] : 0
  end
end

# =============================================================================================
# Side Quest side: where signals come from, places by id or position, routes.
PULSE_MEM = { lock: Mutex.new, vibes: [], grid: nil, grid_at: nil }
PULSE_PUBLIC = %w[story post flare live].freeze   # signals that already show who was there
PULSE_MIN_PEOPLE = 3   # head counts below this aren't shown, so no one person can be picked out

def pulse_grid
  d = Places.data
  PULSE_MEM[:lock].synchronize do
    return PULSE_MEM[:grid] if PULSE_MEM[:grid_at].equal?(d[:list])
    g = Hash.new { |h, k| h[k] = [] }
    d[:list].each { |p| g[[(p['lat'] * 500).floor, (p['lng'] * 500).floor]] << p }   # ~200 m cells
    PULSE_MEM.update(grid: g, grid_at: d[:list])
    g
  end
end

# The place a signal is about: by id, else the closest place within ~70 m (a matching name wins).
def pulse_place_for(id: nil, lat: nil, lng: nil, name: nil)
  if id && !id.to_s.empty? && (p = Places.find(id.to_s)) then return p end
  return nil unless lat && lng
  g = pulse_grid
  ci, cj = (lat * 500).floor, (lng * 500).floor
  near = [-1, 0, 1].product([-1, 0, 1]).flat_map { |a, b| g[[ci + a, cj + b]] }
  nm = name.to_s.downcase[0, 12]
  best = near.map { |p| [p, Places.miles(lat, lng, p['lat'], p['lng']) * 1609.34] }.select { |_, m| m <= 70 }
             .min_by { |p, m| m - (nm.size >= 4 && p['name'].downcase.include?(nm) ? 60 : 0) }
  best && best[0]
end

def pulse_spot_place(v)
  return pulse_place_for(id: v) if v.is_a?(String)
  return nil unless v.is_a?(Hash)
  pulse_place_for(id: v['id'], lat: v['lat'], lng: v['lng'], name: v['name'])
end

# Everything in the last 6 hours that says people are somewhere, as Pulse signals tagged with a place id.
def pulse_signals(d, now = now_ms)
  cut = now - 6 * 3_600_000
  out = []
  (d['quest'] || {}).each do |h, q|
    (q['checkins'] || []).reverse_each do |c|
      break if c['at'] < cut
      next unless c['k'] == 'place'
      out << { 'k' => 'checkin', 'pid' => c['id'], 'at' => c['at'], 'u' => h }
    end
  end
  d['stories'].each do |s|
    next if s['created'].to_i < cut || s['removed'] || s['unreviewed'] || s['vis'] != 'everyone'
    p = pulse_place_for(lat: s['lat'], lng: s['lng'], name: s['place']) or next
    out << { 'k' => 'story', 'pid' => p['id'], 'at' => s['created'], 'u' => s['u'], 'text' => s['caption'],
             'media' => { 't' => 'story', 'id' => s['id'], 'img' => s['img'], 'vid' => s['vid'], 'bg' => s['bg'],
                          'cap' => s['caption'].to_s[0, 60] }.reject { |_, x| x.nil? || x == '' } }
  end
  (d['wall'] || []).each do |w|
    next if w['at'].to_i < cut || w['removed'] || w['unreviewed'] || w['vis'] != 'everyone' || !w['place'].is_a?(Hash)
    p = pulse_spot_place(w['place']) or next
    out << { 'k' => 'post', 'pid' => p['id'], 'at' => w['at'], 'u' => w['u'], 'text' => w['t'],
             'media' => { 't' => 'post', 'id' => w['id'], 'img' => w['img'], 'cap' => w['t'].to_s[0, 60] }.reject { |_, x| x.nil? || x == '' } }
  end
  # Flares (hangouts) while they're on. They're saved as 'broadcast' or 'friends' (never 'everyone'), some inside a
  # group: every one counts toward heat (aggregate only); only reviewed broadcast ones lend their words, and group
  # ones ('party' here) never show a friend there.
  d['posts'].each do |f|
    next if f['removed']
    st, en = f['start'].to_i, (f['end'] || f['start'].to_i + 3 * 3_600_000).to_i
    next unless st <= now + 30 * 60_000 && en > now
    p = pulse_spot_place(f['v']) or next
    vis = f['group'] ? 'party' : f['vis'] || 'broadcast'
    out << { 'k' => 'flare', 'pid' => p['id'], 'at' => [st, now].min, 'u' => f['u'], 'vis' => vis,
             'text' => vis == 'broadcast' && !f['unreviewed'] ? f['t'] : nil }
  end
  live_now.each do |s|   # a stream counts as fresh every time it's announced; its place is the delayed one
    p = pulse_spot_place(s['v']) or next
    out << { 'k' => 'live', 'pid' => p['id'], 'at' => now, 'u' => s['h'], 'text' => s['title'],
             'media' => { 't' => 'live', 'id' => s['id'], 'u' => s['h'], 'title' => s['title'], 'viewers' => s['viewers'] } }
  end
  PULSE_MEM[:lock].synchronize do
    PULSE_MEM[:vibes].reject! { |x| x['at'] < cut }
    out.concat(PULSE_MEM[:vibes].map(&:dup))
  end
  out
end

PULSE_REPORT_M = 300   # a vibe report must come from within this many metres (phones send ~100 m positions)

def pulse_unblocked(d, h, sigs)
  return sigs unless h
  bl = blocked_between(d, h)
  bl.empty? ? sigs : sigs.reject { |s| bl.include?(s['u']) }
end

# The heat map: how busy food & drink places are right now. Live where people are, otherwise what this hour
# usually brings, so the map always shows where it's hot. Live first, then busiest; level >= 0.3 only.
# Places with no signals are cached a minute per ~1 km square (they only change with the hour).
PULSE_HEAT = { lock: Mutex.new, cache: {} }

def pulse_heat(lat, lng, r_km, sigs_by, now = Time.now)
  minute = now.to_i / 60
  key = [(lat * 100).round, (lng * 100).round, r_km.round(1), minute]
  usual = PULSE_HEAT[:lock].synchronize { PULSE_HEAT[:cache][key] }
  b = Pulse.hour_of_week(now)
  kinds = Places::DRINK + Places::FOOD + Places::VENUE
  unless usual
    usual = Places.data[:list].map do |p|
      next unless kinds.include?(p['kind']) && Places.miles(lat, lng, p['lat'], p['lng']) * 1.609 <= r_km
      next if Pulse.open_in_bin?(p['week'], b) == false
      level = pulse_fc(p)[b]
      next if level < 0.1
      { id: p['id'], name: p['name'], kind: p['kind'], lat: p['lat'], lng: p['lng'], level: level.round(2),
        key: Pulse.level_of(level)[1], live: false }
    end.compact
    PULSE_HEAT[:lock].synchronize do
      PULSE_HEAT[:cache].reject! { |k, _| k[3] != minute }
      PULSE_HEAT[:cache][key] = usual
    end
  end
  live = sigs_by.map do |pid, xs|
    p = Places.find(pid) or next
    next if Places.miles(lat, lng, p['lat'], p['lng']) * 1.609 > r_km
    v = Pulse.vibe(pulse_place_in(p), xs, now: now, fc: pulse_fc(p))
    { id: p['id'], name: p['name'], kind: p['kind'], lat: p['lat'], lng: p['lng'], level: v[:level],
      key: v[:key], live: true, hot: v[:hot], people: v[:people] >= PULSE_MIN_PEOPLE ? v[:people] : nil }
  end.compact
  ids = live.map { |x| x[:id] }
  # Hot areas always show: everything at 0.3+ (lively), and when that's thin (1:30 AM on a Tuesday) the busiest of what's
  # open anyway, down to 0.1, up to 25 places, so the map still shows where it's hottest right now.
  rest = usual.reject { |x| ids.include?(x[:id]) }.sort_by { |x| -x[:level] }
  hot = rest.take_while { |x| x[:level] >= 0.3 }
  hot += rest.drop(hot.size).first(25 - hot.size) if hot.size < 25
  rows = live.sort_by { |x| -x[:level] } + hot
  { places: rows.first(150), at: (now.to_f * 1000).to_i }
end

def pulse_place_in(p)
  p.merge('pop' => Popular.scores.key?(p['id']) ? Popular[p['id']] : 40)
end

def pulse_fc(p)
  db = Pulse.db
  Pulse.forecast(pulse_place_in(p), hist: db['p'][p['id']], weeks: db['w'])
end

def pulse_view(p, sigs, now: Time.now, detail: false)
  fc = pulse_fc(p)
  v = Pulse.vibe(pulse_place_in(p), sigs, now: now, fc: fc)
  proof = sigs.select { |s| s['media'] }.sort_by { |s| [s['k'] == 'live' ? 0 : 1, -s['at']] }.first(detail ? 6 : 1)
              .map { |s| s['media'].merge('at' => s['at'], 'by' => s['u']) }
  st = Hours.status(p['week'], Places.now_mow)
  v = v.merge(people: v[:people] >= PULSE_MIN_PEOPLE ? v[:people] : nil, heat: v[:heat].round(1))
  out = { id: p['id'], name: p['name'], kind: p['kind'], lat: p['lat'], lng: p['lng'], zone: Places.zone_of(p)&.dig(:name),
          status: Places.label(st), vibe: v, proof: proof }
  if detail
    hist = Pulse.db['p'][p['id']]
    out[:facts] = Pulse.facts(pulse_place_in(p), fc, now: now, learned_n: hist ? hist['n'].to_f : 0)
    out[:facts][:status] = Places.label(st)
  end
  out
end

# Events with a real spot starting in the next 6 hours (or up to an hour ago), start times parsed once per request:
# the night's pick checks ~250 places, and parsing every event's time for each one took seconds and stalled the server.
def pulse_events_soon(events, now)
  t0, t1 = now.to_f - 3600, now.to_f + 6 * 3600
  events.map do |e|
    next unless e['lat'] && e['geo_precise'] != false
    s = (Time.parse(e['start']).to_f rescue nil)
    e if s && s.between?(t0, t1)
  end.compact
end

def pulse_events_at(p, soon)
  soon.select { |e| Places.miles(e['lat'], e['lng'], p['lat'], p['lng']) * 1609.34 <= 60 }
end

# RSVPs are kept under "e:<uid>"
def pulse_going(d, uid) (d['rsvps']["e:#{uid}"] || d['rsvps'][uid] || {}).count { |_, s| s == 'going' } end

def pulse_trending_events(d, events, now_ms)
  events.map do |e|
    n = pulse_going(d, e['uid'])
    next if n < 2
    g = Pulse.event_growth(e['uid'], n, now_ms)
    next if g < 2
    { uid: e['uid'], title: e['title'], venue: e['venue'], start: e['start'], going: n, why: "+#{g} going today" }
  end.compact.sort_by { |x| -x[:going] }.first(8)
end

def pulse_tick!(force: false)
  now = Time.now
  b = Pulse.hour_of_week(now - 3600)
  db = Pulse.db
  return if !force && db['folded'] == b && db['folded_at'].to_i > now.to_i - 7200
  counts = Hash.new(0)
  events = events_list   # may call the events service: never inside the store lock
  store(write: false) do |d|
    sigs = pulse_signals(d, now_ms).select { |s| s['at'] >= now_ms - 3_600_000 }
    sigs.group_by { |s| s['pid'] }.each { |pid, xs| counts[pid] = Pulse.people(xs) }
    ev = events.to_h { |e| [e['uid'], pulse_going(d, e['uid'])] }.reject { |_, n| n.zero? }
    Pulse.note_events!(ev, now_ms)
  end
  Pulse.fold!(b, counts)
  Pulse.db['folded_at'] = now.to_i
  Pulse.save!
end

PULSE_TICK_SECS = ENV['SQ_PULSE_TICK_SECS'].to_i   # tests: fold every N seconds instead of at :02 each hour

def pulse_background
  Thread.new do
    loop do
      sleep PULSE_TICK_SECS.positive? ? PULSE_TICK_SECS : 60
      begin
        pulse_tick!(force: PULSE_TICK_SECS.positive?) if PULSE_TICK_SECS.positive? || Time.now.min == 2
      rescue StandardError => e
        warn "[pulse] tick: #{e.class}: #{e.message}"
      end
    end
  end
end

def mount_pulse(server)
  # The map's "what's going on near me": notable places (busy, trending, or with fresh proof), zones, events.
  route(server, '/api/pulse', auth: false, get: true) do |_b, h, req|
    limit!("pulse:#{client_ip(req)}", 600, 3600)
    lat = Float(req.query['lat']) rescue 30.2672
    lng = Float(req.query['lng']) rescue -97.7431
    r_km = (req.query['km'] || 3).to_f.clamp(0.3, 25)
    now = Time.now
    events = events_list
    store(write: false) do |d|
      sigs = pulse_unblocked(d, h, pulse_signals(d))
      by = sigs.group_by { |s| s['pid'] }
      rows = by.map do |pid, xs|
        p = Places.find(pid) or next
        next if Places.miles(lat, lng, p['lat'], p['lng']) * 1.609 > r_km
        pulse_view(p, xs, now: now)
      end.compact
      rows.sort_by! { |x| -(x[:vibe][:heat] + (x[:vibe][:hot] ? 5 : 0)) }
      zones = Places::HOTSPOTS.map do |z|
        inz = rows.select { |x| Places.miles(z[:lat], z[:lng], x[:lat], x[:lng]) * 1609.34 <= z[:r] }
        h = inz.sum { |x| x[:vibe][:heat] }
        { id: z[:id], name: z[:name], heat: h.round(1), people: inz.sum { |x| x[:vibe][:people].to_i }, hot: inz.count { |x| x[:vibe][:hot] } }
      end
      { places: rows.first(40), trending: rows.select { |x| x[:vibe][:hot] }.first(8).map { |x| x.slice(:id, :name, :zone, :vibe) },
        zones: zones.select { |z| z[:heat].positive? }.sort_by { |z| -z[:heat] },
        events: pulse_trending_events(d, events, now_ms) }
    end
  end

  # The heat map: busy places around the map's centre (live first, then what this hour usually brings).
  route(server, '/api/pulse/heat', auth: false, get: true) do |_b, h, req|
    limit!("pheat:#{client_ip(req)}", 900, 3600)
    lat = Float(req.query['lat']) rescue 30.2672
    lng = Float(req.query['lng']) rescue -97.7431
    r_km = (req.query['km'] || 4).to_f.clamp(0.5, 12)
    store(write: false) do |d|
      by = pulse_unblocked(d, h, pulse_signals(d)).group_by { |s| s['pid'] }
      pulse_heat(lat, lng, r_km, by)
    end
  end

  # One place: the vibe check, facts and schedule, tonight's hours, proof.
  route(server, '/api/pulse/place', auth: false, get: true) do |_b, h, req|
    limit!("pulse:#{client_ip(req)}", 600, 3600)
    p = Places.find(req.query['id'].to_s) or raise "That place isn't in Side Quest."
    now = Time.now
    events = events_list
    mine = h && PULSE_MEM[:lock].synchronize { PULSE_MEM[:vibes].find { |x| x['u'] == h && x['pid'] == p['id'] && x['at'] > now_ms - 45 * 60_000 } }
    store(write: false) do |d|
      sigs = pulse_unblocked(d, h, pulse_signals(d).select { |s| s['pid'] == p['id'] })
      out = pulse_view(p, sigs, now: now, detail: true)
      out[:mine] = { v: mine['v'], tags: mine['tags'] } if mine   # only ever your own report
      out[:events] = pulse_events_at(p, pulse_events_soon(events, now)).first(3).map { |e| e.slice('uid', 'title', 'start', 'category') }
      out
    end
  end

  # "How's it right now?" from someone who's there. One report moves the level a lot, so the server checks it too:
  # the phone sends its spot rounded to ~100 m and it must be within PULSE_REPORT_M of the place.
  route(server, '/api/pulse/vibe') do |b, h|
    limit!("pvibe:#{h}", 20, 86_400)
    v = b['v'].to_s
    raise 'Pick how it is.' unless Pulse::REPORT.key?(v)
    p = Places.find(b['id'].to_s) or raise "That place isn't in Side Quest."
    la = (Float(b['lat']) rescue nil)
    ln = (Float(b['lng']) rescue nil)
    raise 'Turn on location so we know you are there.' unless la && ln
    raise "You need to be at #{p['name']} to say how it is." if Places.miles(la, ln, p['lat'], p['lng']) * 1609.34 > PULSE_REPORT_M
    tags = Array(b['tags']).map(&:to_s) & Pulse::REPORT_TAGS
    PULSE_MEM[:lock].synchronize do
      mine = PULSE_MEM[:vibes].find { |x| x['u'] == h && x['pid'] == p['id'] && x['at'] > now_ms - 45 * 60_000 }
      PULSE_MEM[:vibes].delete(mine) if mine   # a fresh report replaces your last one there
      PULSE_MEM[:vibes] << { 'k' => 'vibe', 'pid' => p['id'], 'at' => now_ms, 'u' => h, 'v' => v, 'tags' => tags.first(3) }
      PULSE_MEM[:vibes].shift while PULSE_MEM[:vibes].size > 5000
    end
    track!('vibe_report', h) if defined?(track!)
    store(write: false) { |d| { ok: true }.merge(pulse_view(p, pulse_signals(d).select { |s| s['pid'] == p['id'] })) }
  end

  # The one right place for tonight (and a Plan B a short walk from it).
  route(server, '/api/pulse/pick', auth: false) do |b, h, req|
    limit!("ppick:#{h || client_ip(req)}", 120, 3600)
    lat = Float(b['lat']) rescue 30.2672
    lng = Float(b['lng']) rescue -97.7431
    want = Pulse::WANT.key?(b['want']) ? b['want'] : nil
    hours = b['hours'].to_i.then { |x| x.zero? ? 3 : x.clamp(1, 6) }
    kinds = { 'bars' => %w[bar pub beer\ garden brewery], 'clubs' => %w[club], 'food' => Places::FOOD }[b['kind']] || (Places::DRINK + Places::FOOD)
    max_km = (b['km'] || 6).to_f.clamp(0.5, 30)
    now = Time.now
    events = events_list
    soon = pulse_events_soon(events, now)   # parsed once, not per candidate place
    store(write: false) do |d|
      sigs = pulse_signals(d).group_by { |s| s['pid'] }
      friends = h ? friends_of(d, h).to_a : []
      blocked = h ? blocked_between(d, h) : Set.new
      taste = h ? taste_for(d, h) : nil
      liked = (taste || {}).values_at('venues', 'food').compact.flatten(1).map { |n, _| n.to_s.downcase }
      out_now = h && defined?(friends_out) ? (friends_out(d, h) rescue []) : []
      pool = Places.data[:list].select { |p| kinds.include?(p['kind']) && Places.miles(lat, lng, p['lat'], p['lng']) * 1.609 <= max_km }
      pool = pool.sort_by { |p| -(Popular[p['id']] + (sigs[p['id']] ? 100 : 0)) }.first(250)   # the known and the busy
      cands = pool.map do |p|
        xs = (sigs[p['id']] || []).reject { |s| blocked.include?(s['u']) }
        fc = pulse_fc(p)
        v = Pulse.vibe(pulse_place_in(p), xs, now: now, fc: fc)
        next if v[:open] == false
        # friends there: only what they already show (public stories/posts, flares, live) or opted-in check-ins
        here = (xs.select { |s| PULSE_PUBLIC.include?(s['k']) && s['vis'] != 'party' }.map { |s| s['u'] } & friends) |
               out_now.select { |f| f[:k] == 'place' && f[:id] == p['id'] }.map { |f| f[:h] }
        evs = pulse_events_at(p, soon).first(2).map do |e|
          st = (Time.parse(e['start']) rescue now)
          { title: e['title'][0, 50], when: st <= now ? 'on now' : st.strftime('at %-l:%M %p').sub(':00', ''),
            fits: (taste && (taste['event_types'] || []).to_h.key?(e['category'])) || false }
        end
        fit = liked.any? { |n| n == p['name'].downcase || p['cuisine'].to_a.any? { |c| n.include?(c.to_s.downcase) } } ? 1.0 : 0.0
        { place: pulse_place_in(p), fc: fc, vibe: v, km: Places.miles(lat, lng, p['lat'], p['lng']) * 1.609,
          friends: here.uniq, events: evs, fit: fit, media: xs.count { |s| s['media'] } }
      end.compact
      ranked = Pulse.rank(cands, want: want, hours: hours, now: now)
      top = ranked.first(5)
      pick = top.first
      plan_b = pick && ranked.drop(1).find { |c| Places.miles(pick[:place]['lat'], pick[:place]['lng'], c[:place]['lat'], c[:place]['lng']) <= 0.3 }
      view = lambda do |c|
        p = c[:place]
        { id: p['id'], name: p['name'], kind: p['kind'], lat: p['lat'], lng: p['lng'], vibe: c[:vibe].slice(:key, :e, :label, :sure, :hot, :words),
          why: c[:why], stays: c[:stay], score: c[:score],
          proof: (sigs[p['id']] || []).select { |s| s['media'] }.max_by { |s| s['at'] }&.dig('media') }
      end
      { pick: pick && view.(pick), plan_b: plan_b && view.(plan_b), more: top.drop(1).reject { |c| c.equal?(plan_b) }.map(&view),
        want: want, hours: hours }
    end
  end

  # Stories, posts and live streams worth watching to decide where to go, best first.
  route(server, '/api/pulse/feed', auth: false, get: true) do |_b, h, req|
    limit!("pfeed:#{h || client_ip(req)}", 600, 3600)
    lat = Float(req.query['lat']) rescue 30.2672
    lng = Float(req.query['lng']) rescue -97.7431
    now = now_ms
    store(write: false) do |d|
      sigs = pulse_signals(d)
      by = sigs.group_by { |s| s['pid'] }
      friends = h ? friends_of(d, h).to_a : []
      blocked = h ? blocked_between(d, h) : Set.new
      t = Time.now
      heat_x = Hash.new do |hh, pid|
        p = Places.find(pid)
        hh[pid] = p ? (v = Pulse.vibe(pulse_place_in(p), by[pid] || [], now: t, fc: pulse_fc(p)); (v[:heat] + 1) / (v[:usual] * Pulse::FULL_HEAT + 1) - 1) : 0
      end
      items = sigs.select { |s| s['media'] && !blocked.include?(s['u']) }.map do |s|
        p = Places.find(s['pid'])
        st = s['media']['t'] == 'story' ? d['stories'].find { |x| x['id'] == s['media']['id'] } : nil
        wp = s['media']['t'] == 'post' ? (d['wall'] || []).find { |x| x['id'] == s['media']['id'] } : nil
        { id: s['media']['id'], type: s['media']['t'], u: s['u'], at: s['at'], pid: s['pid'], place: p && p['name'],
          likes: (st && st['likes']&.size) || (wp && wp['likes']&.size) || 0, views: (st && st['views']&.size) || s['media']['viewers'].to_i,
          comments: (wp && wp['comments']&.size) || 0, friend: friends.include?(s['u']),
          km: p ? Places.miles(lat, lng, p['lat'], p['lng']) * 1.609 : 10, heat_x: [heat_x[s['pid']], 0].max,
          img: s['media']['img'], vid: s['media']['vid'], bg: s['media']['bg'], cap: s['media']['cap'], title: s['media']['title'] || s['text'].to_s[0, 80] }
      end
      { items: Pulse.rank_media(items, now).first(40).map { |m| m.reject { |k, _| %i[raw heat_x km].include?(k) }.merge(km: m[:km].round(1)) } }
    end
  end
  pulse_background unless ENV['SQ_PULSE_NOBG']
end
