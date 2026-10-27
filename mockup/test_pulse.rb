# Pulse engine (pulse.rb): forecasts, heat, vibe check, facts, picks, media ranking. No server: ruby test_pulse.rb
ENV['SQ_PULSE_FILE'] = File.join(Dir.tmpdir, "pulse-test-#{$$}.json") if require('tmpdir')
require_relative 'hours'
require_relative 'pulse'

$fails = 0; $n = 0
def ok(name, cond, info = nil)
  $n += 1
  puts "#{cond ? '✓' : '✗'} #{name}#{cond || !info ? '' : "  (#{info})"}"
  $fails += 1 unless cond
end

def at(day, hour, min = 0) Time.new(2026, 10, 26 + day, hour, min) end   # 2026-10-26 is a Monday
def ms(t) (t.to_f * 1000).to_i end
B = ->(day, h) { day * 24 + h }

# ---- prior curves ----
bar = Pulse.prior_curve('bar'); club = Pulse.prior_curve('club'); cafe = Pulse.prior_curve('cafe'); rest = Pulse.prior_curve('restaurant')
ok 'curves are 168 hours scaled to 1', [bar, club, cafe, rest].all? { |c| c.size == 168 && (c.max - 1).abs < 1e-9 }
ok 'bars: Friday 11 PM beats Friday 3 PM', bar[B[4, 23]] > 2 * bar[B[4, 15]]
ok 'bars: Saturday night beats Tuesday night', bar[B[5, 23]] > 1.5 * bar[B[1, 23]]
ok "bars: Saturday 1 AM is Friday night's crowd, busier than Tuesday 1 AM", bar[B[5, 1]] > 1.5 * bar[B[1, 1]]
ok 'clubs peak after midnight on weekends', club.each_with_index.max_by { |x, _| x }[1].then { |b| [5, 6].include?(b / 24) && (b % 24) <= 2 }
ok 'cafés peak in the morning', (8..10).include?(cafe.each_with_index.max_by { |x, _| x }[1] % 24)
ok 'restaurants: dinner and lunch beat 4 PM', rest[B[2, 19]] > rest[B[2, 16]] && rest[B[2, 12]] > rest[B[2, 16]]
ok 'restaurants: weekend brunch', rest[B[6, 11]] > 1.5 * rest[B[2, 11]]

# ---- forecast with real hours ----
week = Hours.parse('Mo-Su 16:00-02:00')
fc = Pulse.forecast({ 'kind' => 'bar', 'week' => week, 'pop' => 90 })
ok 'closed hours forecast 0', fc[B[2, 10]].zero? && fc[B[2, 3]].zero?
ok 'open late hours are positive', fc[B[4, 23]].positive? && fc[B[5, 1]].positive?
low = Pulse.forecast({ 'kind' => 'bar', 'week' => week, 'pop' => 10 })
ok 'better-known places forecast busier', fc[B[4, 23]] > low[B[4, 23]]
unknown = Pulse.forecast({ 'kind' => 'bar' })
ok 'unknown hours keep the usual shape', unknown[B[4, 23]].positive? && unknown[B[2, 10]] < 0.1
# learned history pulls the shape: this bar is a Tuesday trivia spot
hist = { 's' => Array.new(168, 0.0), 'n' => 200 }; hist['s'][B[1, 20]] = 12.0
weeks = Array.new(168, 4.0)
learned = Pulse.forecast({ 'kind' => 'bar', 'week' => week, 'pop' => 90 }, hist: hist, weeks: weeks)
ok 'history moves the forecast to when people really go', learned[B[1, 20]] > 2 * fc[B[1, 20]] && learned[B[1, 20]] > learned[B[4, 23]]

# ---- heat ----
now = at(4, 23)
one = (1..6).map { |i| { 'k' => 'checkin', 'pid' => 'x', 'at' => ms(now) - i * 60_000, 'u' => 'spammer' } }
many = (1..6).map { |i| { 'k' => 'checkin', 'pid' => 'x', 'at' => ms(now) - i * 60_000, 'u' => "u#{i}" } }
ok 'one person counts once (spam-proof)', Pulse.heat(one, ms(now)) < 0.4 * Pulse.heat(many, ms(now)), [Pulse.heat(one, ms(now)), Pulse.heat(many, ms(now))]
old = [{ 'k' => 'checkin', 'pid' => 'x', 'at' => ms(now) - 150 * 60_000, 'u' => 'a' }]
fresh = [{ 'k' => 'checkin', 'pid' => 'x', 'at' => ms(now), 'u' => 'a' }]
ok 'heat fades (75 min half-life for check-ins)', (Pulse.heat(old, ms(now)) - Pulse.heat(fresh, ms(now)) / 4).abs < 0.01
ok 'future or ancient signals are ignored', Pulse.heat([{ 'k' => 'story', 'at' => ms(now) + 60_000, 'u' => 'a' }, { 'k' => 'story', 'at' => ms(now) - 86_400_000, 'u' => 'b' }], ms(now)).zero?

# ---- vibe check ----
place = { 'kind' => 'bar', 'week' => week, 'pop' => 70 }
quiet_tue = Pulse.vibe(place, [], now: at(1, 17))
ok 'no signals: the usual for that hour, marked usual', quiet_tue[:sure] == 'usual' && quiet_tue[:level] == Pulse.forecast(place)[B[1, 17]].round(2)
closed = Pulse.vibe(place, [], now: at(1, 11))
ok 'closed now = 0 and open false', closed[:level].zero? && closed[:open] == false && closed[:key] == 'quiet'
crowd = (1..8).map { |i| { 'k' => 'checkin', 'pid' => 'x', 'at' => ms(at(1, 17)) - i * 120_000, 'u' => "u#{i}" } }
busy = Pulse.vibe(place, crowd, now: at(1, 17))
ok 'a crowd on a quiet Tuesday afternoon reads busy and trending', busy[:level] > 0.6 && busy[:hot] && busy[:sure] == 'high', busy
rep = [{ 'k' => 'vibe', 'v' => 'dead', 'at' => ms(at(4, 23)) - 5 * 60_000, 'u' => 'z', 'tags' => [] }]
dead = Pulse.vibe(place, rep, now: at(4, 23))
ok "someone there saying it's dead beats Friday's forecast", dead[:level] < 0.3 && dead[:sure] == 'high', dead[:level]
said = [{ 'k' => 'story', 'at' => ms(now) - 60_000, 'u' => 'a', 'text' => 'DJ is going off, huge line outside' },
        { 'k' => 'vibe', 'v' => 'packed', 'tags' => %w[line cover], 'at' => ms(now) - 60_000, 'u' => 'b' }]
w = Pulse.vibe(place, said, now: now)[:words]
ok 'words people used, most said first', w.first == 'line' && w.include?('DJ') && w.include?('cover'), w

# ---- facts & schedule ----
f = Pulse.facts({ 'kind' => 'bar', 'week' => week, 'pop' => 80 }, fc, now: at(4, 18))
ok 'busiest window tonight', f[:peak].to_s =~ /Busiest (10|11) PM/, f[:peak]
ok 'best time to get there is before the peak', f[:arrive].to_s =~ /Get there by (8|9|10):30 PM/, f[:arrive]
ok 'last call for a 2 AM bar', f[:last_call] == 'Last call ~1:45 AM'
rest = { 'kind' => 'restaurant', 'pop' => 90 }   # dinner rush after a quiet afternoon (hours unknown)
fr = Pulse.facts(rest, Pulse.forecast(rest), now: at(1, 12))
ok "a dinner rush doesn't say to get there at lunch", fr[:arrive].nil? || fr[:arrive] =~ /Get there by ([4-7]):30 PM/, [fr[:peak], fr[:arrive]]
ok 'says what the forecast is based on', f[:based_on] =~ /usually/
ok 'hours run 5 AM to 4 AM', f[:hours].size == 24 && f[:hours].first[:h] == 5
after_midnight = Pulse.facts({ 'kind' => 'bar', 'week' => week, 'pop' => 80 }, fc, now: at(5, 1))
ok "at 1 AM Saturday it's still Friday's night", after_midnight[:hours].first[:h] == 5 && after_midnight[:peak]
f2 = Pulse.facts({ 'kind' => 'restaurant', 'week' => Hours.parse('Mo-Su 11:00-22:00'), 'pop' => 60 }, Pulse.forecast({ 'kind' => 'restaurant', 'week' => Hours.parse('Mo-Su 11:00-22:00'), 'pop' => 60 }), now: at(2, 9))
ok 'restaurant: dinner peak, quiet mid-afternoon, no last call', f2[:peak].to_s =~ /(6|7) PM/ && f2[:quiet].to_s =~ /(3|4|9) PM/ && !f2[:last_call], f2

# ---- the pick: one place for the whole night ----
mk = lambda do |name, fcx, km, extra = {}|
  { place: { 'name' => name, 'pop' => 60 }, fc: fcx, vibe: { level: fcx[B[4, 21]], e: '😌', label: 'x', sure: 'usual', open: true },
    km: km, friends: [], events: [], fit: 0, media: 0 }.merge(extra)
end
lively_all_night = Array.new(168, 0.62)
fades = Array.new(168, 0.0); fades[B[4, 21]] = 0.65   # good for an hour, then closes
ranked = Pulse.rank([mk.('Fades', fades, 0.4), mk.('Stays', lively_all_night, 0.9)], want: 'lively', hours: 3, now: at(4, 21))
ok 'prefers the place that stays good all night over a closer one-hour stop', ranked.first[:place]['name'] == 'Stays', ranked.map { |c| [c[:place]['name'], c[:score]] }
ok 'says why: stays good', ranked.first[:why].any? { |x| x =~ /whole night/ }, ranked.first[:why]
packed = Array.new(168, 0.95)
r2 = Pulse.rank([mk.('Packed', packed, 0.5), mk.('Chill', Array.new(168, 0.35), 0.5)], want: 'chill', hours: 3, now: at(4, 21))
ok 'wanting chill skips the packed one', r2.first[:place]['name'] == 'Chill'
r3 = Pulse.rank([mk.('Mine', lively_all_night, 2.0, friends: %w[ana ben]), mk.('Other', lively_all_night, 1.5)], want: 'lively', hours: 3, now: at(4, 21))
ok 'friends being there wins a tie', r3.first[:place]['name'] == 'Mine' && r3.first[:why].first =~ /@ana, @ben are there/, r3.first[:why]
r4 = Pulse.rank([mk.('Far', lively_all_night, 15), mk.('Near', lively_all_night, 0.5)], want: 'lively', hours: 3, now: at(4, 21))
ok 'distance costs', r4.first[:place]['name'] == 'Near'

# ---- media feed ----
t0 = ms(now)
items = [{ id: 'a1', type: 'story', u: 'amy', at: t0 - 600_000, likes: 9, views: 50, pid: 'p1', km: 1 },
         { id: 'a2', type: 'story', u: 'amy', at: t0 - 500_000, likes: 9, views: 50, pid: 'p1', km: 1 },
         { id: 'a3', type: 'story', u: 'amy', at: t0 - 400_000, likes: 9, views: 50, pid: 'p1', km: 1 },
         { id: 'b1', type: 'story', u: 'bo', at: t0 - 900_000, likes: 4, views: 20, pid: 'p2', km: 2 },
         { id: 'l1', type: 'live', u: 'cy', at: t0, views: 3, pid: 'p3', km: 3 },
         { id: 'o1', type: 'post', u: 'dee', at: t0 - 5 * 86_400_000, likes: 30, pid: 'p4', km: 1 }]
feed = Pulse.rank_media(items, t0).map { |m| m[:id] }
ok 'live streams lead the feed', feed.first == 'l1', feed
ok 'one author does not take the top three', feed.first(3).count { |id| id.start_with?('a') } <= 1, feed
ok 'a five-day-old post sinks below fresh stories', feed.index('o1') > feed.index('b1'), feed
hot = Pulse.rank_media([items[3], items[3].merge(id: 'b2', u: 'ed', pid: 'p9', heat_x: 2)], t0).first[:id]
ok 'media from a place busier than usual ranks higher', hot == 'b2'

# ---- history ----
Pulse.fold!(B[4, 22], { 'p1' => 5 })
Pulse.fold!(B[4, 22], { 'p1' => 5 })
d = Pulse.db
ok 'fold keeps decayed counts and weeks', (d['p']['p1']['s'][B[4, 22]] - 9.25).abs < 1e-6 && (d['w'][B[4, 22]] - 1.85).abs < 1e-6 && d['p']['p1']['n'] == 10
Pulse.save!
ok 'saved to the pulse file', File.exist?(Pulse::FILE) && JSON.parse(File.read(Pulse::FILE))['p']['p1']
Pulse.note_events!({ 'e1' => 2 }, t0 - 30 * 3_600_000)
Pulse.note_events!({ 'e1' => 9 }, t0)
ok 'event RSVP growth over the day', Pulse.event_growth('e1', 9, t0) == 7
File.delete(Pulse::FILE) rescue nil

puts "\n#{$n - $fails}/#{$n} passed"
exit($fails.zero? ? 0 : 1)
