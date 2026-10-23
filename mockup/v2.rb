# Side Quest V2 on the server: notifications, quests & check-ins, saves, event discussion, invites, share pages with
# link previews, first-party analytics and event reminders. Loaded by server.rb; uses its helpers (store, route,
# limit!, moderate, blocked_between, friends_of, now_ms) and keeps everything in the same data file, under new keys
# only (nothing old is renamed or removed).
require 'json'
require 'cgi'
require_relative 'webpush'

# ---------------------------------------------------------------------------------------------
# Notifications: per person, newest last, capped. Never across a block; never about yourself.
NOTIF_MAX = 120
NOTIF_TYPES = %w[freq friend down going chat join tag like quest joined remind invite].freeze

def notify!(d, to, type, from: nil, ref: nil, text: nil)
  return unless to && d['users'][to] && to != from && NOTIF_TYPES.include?(type)
  return if (d['users'][to]['mute'] || []).include?(type)   # they turned this kind off
  return if from && blocked_between(d, to).include?(from)
  list = ((d['notifs'] ||= {})[to] ||= [])
  # the same thing twice within an hour (likes, chat bursts) folds into one, bumped to the top
  if (old = list.find { |n| n['t'] == type && n['from'] == from && n['ref'] == ref && n['at'] > now_ms - 3_600_000 })
    list.delete(old)
  end
  list << { 'id' => "n#{SecureRandom.hex(5)}", 't' => type, 'from' => from, 'ref' => ref, 'text' => text.to_s[0, 160],
            'at' => now_ms, 'read' => false }
  list.shift while list.size > NOTIF_MAX
  PUSH_Q << [to, type, ref, text.to_s[0, 160]] if (d['push'] || {})[to]&.any?   # phones that said yes get it too
end

# ---------------------------------------------------------------------------------------------
# Push to phones (Web Push): the server's VAPID key lives in data/vapid.json (only this server can read it); each
# person's subscriptions in d['push'][h] (max 5 devices). Sending happens on a background thread.
VAPID_FILE = File.join(__dir__, 'data', 'vapid.json')
PUSH_Q = Queue.new
PUSH_SUBJECT = ENV['SQ_PUSH_CONTACT'] || 'mailto:kevrkid@gmail.com'
def vapid_key
  @vapid_key ||= begin
    if File.file?(VAPID_FILE)
      WebPush.key_from_private(WebPush.unb64u(JSON.parse(File.read(VAPID_FILE))['private']))
    else
      k = WebPush.new_key
      FileUtils.mkdir_p(File.dirname(VAPID_FILE))
      File.open(VAPID_FILE, 'w', 0o600) { |f| f.write(JSON.generate(private: WebPush.b64u(k.private_key.to_s(2).rjust(32, "\x00".b)), public: WebPush.b64u(WebPush.pub_raw(k)))) }
      k
    end
  end
end
def vapid_public() WebPush.b64u(WebPush.pub_raw(vapid_key)) end

def push_url(type, ref)
  r = ref.to_s
  return "/?ev=#{r.sub('e:', '')}" if r.start_with?('e:')
  return "/?g=#{r.sub('g:', '')}" if r.start_with?('g:')
  type == 'quest' ? '/?quests=1' : '/?inbox=1'
end

def push_worker
  Thread.new do
    loop do
      to, type, ref, text = PUSH_Q.pop
      begin
        subs = store(write: false) { |d| ((d['push'] || {})[to] || []).map(&:dup) }
        gone = subs.select do |sub|
          WebPush.deliver(sub, { title: 'Side Quest', body: text, tag: "#{type}:#{ref}", url: push_url(type, ref) }, vapid_key, PUSH_SUBJECT) == :gone
        end
        store { |d| (d['push'][to] || []).reject! { |x| gone.any? { |g| g['endpoint'] == x['endpoint'] } } } unless gone.empty?
      rescue StandardError => e
        warn "[push] #{e.message[0, 120]}"
      end
    end
  end
end

# ---------------------------------------------------------------------------------------------
# Quests: challenges that get people out. Progress is worked out here from check-ins and what people did;
# the phone only claims "I'm at <place id>" after checking it's within ~150 m (exact GPS never leaves it).
QUESTS = [
  { id: 'history', e: '🪧', name: 'History buff', desc: 'Check in at 5 historical markers or landmarks', goal: 5, xp: 150 },
  { id: 'culture', e: '🖼️', name: 'Culture hound', desc: 'Visit 3 museums, murals or statues', goal: 3, xp: 100 },
  { id: 'tacos', e: '🌮', name: 'Taco crawl', desc: 'Check in at 3 taco or Tex-Mex spots', goal: 3, xp: 100 },
  { id: 'outdoors', e: '🌲', name: 'Touch grass', desc: 'Check in at 3 parks, lakes or trails', goal: 3, xp: 100 },
  { id: 'shows', e: '🎸', name: 'Live and loud', desc: 'Check in at 2 events (shows, games, comedy)', goal: 2, xp: 120 },
  { id: 'nightowl', e: '🦉', name: 'Night owl', desc: 'Check in somewhere between 11 PM and 4 AM', goal: 1, xp: 60 },
  { id: 'explorer', e: '🧭', name: 'Explorer', desc: 'Check in in 3 different hot spots', goal: 3, xp: 120 },
  { id: 'squad', e: '🤝', name: 'Squad up', desc: 'Make 3 friends on Side Quest', goal: 3, xp: 100 },
  { id: 'flare', e: '🔥', name: 'Light a flare', desc: 'Post a flare and see who\'s down', goal: 1, xp: 40 },
  { id: 'story', e: '📸', name: 'Storyteller', desc: 'Share 3 stories', goal: 3, xp: 60 },
  { id: 'recruiter', e: '💌', name: 'Bring a friend', desc: 'Invite someone who joins', goal: 1, xp: 80 },
  { id: 'regular', e: '📅', name: 'Regular', desc: 'Get out 3 weeks in a row', goal: 3, xp: 150 }
].freeze
CHECKIN_XP = 10
# One check-in quest a week is the featured one: 1.5x XP if you finish it that week.
FEATURED = %w[history tacos outdoors culture shows explorer nightowl].freeze
def featured_quest(t = Time.now) QUESTS.find { |q| q[:id] == FEATURED[t.strftime('%V').to_i % FEATURED.size] } end
CHECKIN_RE = /\A[A-Za-z0-9:_.-]{1,60}\z/

def quest_rec(d, h)
  q = ((d['quest'] ||= {})[h] ||= {})
  q['xp'] ||= 0; q['done'] ||= {}; q['n'] ||= {}; q['checkins'] ||= []
  q
end

def quest_bump!(d, h, key, by = 1)
  return unless d['users'][h]
  q = quest_rec(d, h)
  q['n'][key] = q['n'][key].to_i + by
  quest_award!(d, h)
end

def week_key(t) Time.at(t / 1000).strftime('%G-%V') end

def quest_progress(d, h)
  q = quest_rec(d, h)
  c = q['checkins']
  kinds = ->(*ks) { c.count { |x| (x['tags'] & ks).any? } }
  weeks = c.map { |x| week_key(x['at']) }.uniq.sort
  run = 0; best = 0; prev = nil
  weeks.each do |w|
    y, n = w.split('-').map(&:to_i)
    run = prev && ((prev[0] == y && prev[1] == n - 1) || (prev[0] == y - 1 && n == 1 && prev[1] >= 52)) ? run + 1 : 1
    best = [best, run].max; prev = [y, n]
  end
  {
    'history' => kinds.('marker', 'landmark'), 'culture' => kinds.('museum', 'art'), 'tacos' => kinds.('tacos'),
    'outdoors' => kinds.('outdoors'), 'shows' => kinds.('event'), 'nightowl' => kinds.('late'),
    'explorer' => c.map { |x| x['zone'] }.compact.uniq.size, 'squad' => friends_of(d, h).size,
    'flare' => q['n']['flare'].to_i, 'story' => q['n']['story'].to_i, 'recruiter' => q['n']['recruit'].to_i, 'regular' => best
  }
end

def quest_award!(d, h)
  q = quest_rec(d, h)
  prog = quest_progress(d, h)
  QUESTS.each do |qd|
    next if q['done'][qd[:id]] || prog[qd[:id]].to_i < qd[:goal]
    q['done'][qd[:id]] = now_ms
    xp = featured_quest[:id] == qd[:id] ? (qd[:xp] * 1.5).round : qd[:xp]
    q['xp'] += xp
    notify!(d, h, 'quest', ref: qd[:id], text: "#{qd[:e]} Quest complete: #{qd[:name]} (+#{xp} XP#{xp > qd[:xp] ? ', quest of the week' : ''})")
  end
end

# Friends out right now: check-ins from the last 3 hours by friends who chose to share them (off by default).
# Only the place's name and kind, never a position.
def friends_out(d, h)
  cut = now_ms - 3 * 3_600_000
  hidden = blocked_between(d, h)
  friends_of(d, h).to_a.reject { |f| hidden.include?(f) }.flat_map do |f|
    next [] unless d['users'][f]&.dig('share_checkins')
    c = ((d['quest'] || {})[f] || {})['checkins'].to_a.reverse.find { |x| x['at'] > cut }
    c ? [{ h: f, name: c['name'], k: c['k'], id: c['id'], at: c['at'] }] : []
  end.sort_by { |x| -x[:at] }.first(10)
end

def level_of(xp) (Math.sqrt(xp.to_i / 50.0)).floor + 1 end

def quest_view(d, h)
  q = quest_rec(d, h)
  prog = quest_progress(d, h)
  lvl = level_of(q['xp'])
  { xp: q['xp'], level: lvl, next_at: (lvl**2) * 50, this_at: ((lvl - 1)**2) * 50, featured: featured_quest[:id],
    streak: prog['regular'], checkins: q['checkins'].size,
    quests: QUESTS.map { |qd| qd.merge(have: [prog[qd[:id]].to_i, qd[:goal]].min, done: q['done'][qd[:id]]) },
    recent: q['checkins'].last(8).reverse }
end

# What a check-in is, from our own data (never from the phone): its name, where, and which quests it counts for.
def checkin_target(k, id)
  case k
  when 'sight'
    s = Sights.find(id) or return nil
    tags = { 'marker' => %w[marker], 'landmark' => %w[landmark], 'museum' => %w[museum], 'art' => %w[art], 'view' => %w[art],
             'nature' => %w[outdoors], 'venue' => %w[landmark] }[s['kind']] || []
    { name: s['name'], lat: s['lat'], lng: s['lng'], tags: tags }
  when 'place'
    p = Places.find(id) or return nil
    tags = []
    tags << 'tacos' if "#{p['cuisine']} #{p['name']}" =~ /taco|mexican|tex-mex|tex_mex|burrito/i
    { name: p['name'], lat: p['lat'], lng: p['lng'], tags: tags }
  when 'area'
    a = outdoor_areas.find { |x| x['id'] == id } or return nil
    { name: a['name'], lat: a['c'][0], lng: a['c'][1], tags: %w[outdoors] }
  when 'event'
    e = event_by_uid(id.sub(/\Ae:/, '')) or return nil
    return nil unless e['lat']
    { name: e['title'], lat: e['lat'], lng: e['lng'], tags: %w[event], ev: e }
  end
end

OUTDOOR_CACHE = { at: nil, list: [] }
def outdoor_areas
  file = ENV['SQ_OUTDOORS_FILE'] ? File.join(ROOT, ENV['SQ_OUTDOORS_FILE']) : File.join(ROOT, 'data', 'outdoors.json')
  m = File.file?(file) ? File.mtime(file) : nil
  if m != OUTDOOR_CACHE[:at]
    OUTDOOR_CACHE[:at] = m
    OUTDOOR_CACHE[:list] = m ? (JSON.parse(File.read(file))['areas'] rescue []) : []
  end
  OUTDOOR_CACHE[:list]
end

# Events come from the events service through the same 5-minute cache the app uses.
def events_list
  if Time.now.to_f - EVENTS_CACHE[:at] > 300 || !EVENTS_CACHE[:body]
    horizon = (Time.now + 45 * 86_400).strftime('%Y-%m-%dT00:00:00')
    uri = URI("#{EVENTS_API}/api/events?limit=1000&end=#{horizon}")
    r = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 15) { |http| http.get(uri.request_uri) }
    EVENTS_CACHE.update(at: Time.now.to_f, body: EventFilter.clean(r.body)) if r.code == '200'
  end
  (JSON.parse(EVENTS_CACHE[:body].to_s)['events'] rescue nil) || []
rescue StandardError
  (JSON.parse(EVENTS_CACHE[:body].to_s)['events'] rescue nil) || []
end

EV_INDEX = { body: nil, by: {} }
def event_by_uid(uid)
  events_list if Time.now.to_f - EVENTS_CACHE[:at] > 300
  if EV_INDEX[:body] != EVENTS_CACHE[:body]   # index once per refresh, not per lookup
    EV_INDEX[:by] = events_list.to_h { |e| [e['uid'], e] }
    EV_INDEX[:body] = EVENTS_CACHE[:body]
  end
  EV_INDEX[:by][uid.to_s]
end
# The event's real title (never the one a browser sent), for anything other people will read.
def event_title(id) (event_by_uid(id.to_s.sub(/\Ae:/, '')) || {})['title'].to_s[0, 70] end

# ---------- Taste: what someone has enjoyed, so Scout recommends more of it ----------
# Remembered from their own taps (going / interested, saves, check-ins) in d['taste'][h], newest last, because events
# vanish from the events service once they're over. Only Scout reads it, and only for that person.
TASTE_W = { 'going' => 3.0, 'checkin' => 3.0, 'save' => 2.0, 'interested' => 1.5 }.freeze
TASTE_HOW = { 'going' => 'Went to', 'checkin' => 'Checked in at', 'save' => 'Saved', 'interested' => 'Interested in' }.freeze

def taste_item(k, id)
  case k
  when 'event'
    e = event_by_uid(id.to_s.sub(/\Ae:/, '')) or return nil
    { 'k' => 'event', 'id' => "e:#{e['uid']}", 'name' => e['title'].to_s[0, 80], 'cat' => e['category'].to_s,
      'venue' => e['venue'].to_s.strip.empty? ? nil : e['venue'].to_s[0, 60] }
  when 'place'
    p = Places.find(id) or return nil
    food = p['cuisine'].to_s.split(/[;,]/).first.to_s.strip.tr('_', ' ')
    { 'k' => 'place', 'id' => id, 'name' => p['name'].to_s[0, 80], 'food' => food.empty? ? p['kind'].to_s : food }
  when 'sight'
    s = Sights.find(id) or return nil
    { 'k' => 'sight', 'id' => id, 'name' => s['name'].to_s[0, 80], 'kind' => s['kind'].to_s }
  end
rescue StandardError
  nil
end

def remember_taste!(d, h, how, k, id)
  item = taste_item(k, id) or return
  list = ((d['taste'] ||= {})[h] ||= [])
  list.reject! { |x| x['id'] == item['id'] && x['how'] == how }
  list << item.merge('how' => how, 'at' => now_ms).reject { |_, v| v.nil? }
  list.shift while list.size > 120
end

def forget_taste!(d, h, id, hows)
  ((d['taste'] || {})[h] || []).reject! { |x| x['id'] == id && hows.include?(x['how']) }
end

# People who used the app before this existed: start from what's already saved (RSVPs, saves, check-ins).
def seed_taste!(d, h)
  return if (d['taste'] ||= {}).key?(h)
  d['taste'][h] = []
  (d['rsvps'] || {}).each { |id, who| remember_taste!(d, h, who[h], 'event', id) if %w[going interested].include?(who[h]) }
  ((d['saves'] || {})[h] || []).each { |x| remember_taste!(d, h, 'save', x['k'], x['id']) }
  (((d['quest'] || {})[h] || {})['checkins'] || []).each { |x| remember_taste!(d, h, 'checkin', x['k'], x['id']) }
end

# What they like, weighted: going / check-ins count most, and older things fade (half as much every two months).
def taste_for(d, h)
  list = (d['taste'] || {})[h] || []
  return nil if list.empty?
  now = now_ms
  w = ->(x) { TASTE_W[x['how']].to_f * 0.5**((now - x['at'].to_i) / (60 * 86_400_000.0)) }
  top = lambda do |f|
    list.each_with_object(Hash.new(0.0)) { |x, m| v = f.(x); m[v] += w.(x) if v && !v.empty? }
        .sort_by { |_, s| -s }.first(5).map { |v, s| [v, s.round(1)] }
  end
  { 'event_types' => top.(->(x) { x['cat'] if x['k'] == 'event' }),
    'venues' => top.(->(x) { x['k'] == 'event' ? x['venue'] : (x['name'] if x['k'] == 'place' && x['how'] == 'checkin') }),
    'food' => top.(->(x) { x['food'] if x['k'] == 'place' }),
    'sights' => top.(->(x) { x['kind'] if x['k'] == 'sight' }),
    'recent' => list.last(8).reverse.map do |x|
      "#{TASTE_HOW[x['how']]} #{x['name']}#{x['venue'] ? " at #{x['venue']}" : ''} (#{Time.at(x['at'].to_i / 1000).strftime('%b %-d')})"
    end }.reject { |_, v| v.empty? }
end

# Upcoming events (next 7 days) that fit their taste: the kinds and venues they've enjoyed, best fit first.
def taste_events(taste, near, limit = 8)
  return [] unless taste
  cats = (taste['event_types'] || []).to_h
  venues = (taste['venues'] || []).to_h
  return [] if cats.empty? && venues.empty?
  now = Time.now
  events_list.map do |e|
    t = (Time.parse(e['start'].to_s) rescue nil)
    next unless t && t > now - 3600 && t < now + 7 * 86_400
    c, v = cats[e['category']].to_f, venues[e['venue']].to_f
    score = c + v * 1.5
    next if score <= 0
    why = [v > 0 ? "you've been to #{e['venue']}" : nil, c > 0 ? "you like #{e['category'].to_s.tr('_', ' ')}" : nil].compact.join(' and ')
    mi = near && e['lat'] ? (Math.hypot((e['lat'].to_f - near[0]) * 69.0, (e['lng'].to_f - near[1]) * 59.7)).round(1) : nil
    tba = e['start'].to_s =~ /T00:00(:00)?/   # the scrapers' "time not listed"
    [score - (t - now) / 86_400.0 * 0.1, { 'id' => "e:#{e['uid']}", 'title' => e['title'].to_s[0, 90], 'type' => e['category'],
                                          'when' => t.strftime(tba ? '%a %b %-d (time TBA)' : '%a %b %-d, %-l:%M %p'), 'venue' => e['venue'], 'mi' => mi,
                                          'fits' => why }.compact]
  end.compact.sort_by { |s, _| -s }.first(limit).map(&:last)
end

# Invite links carry a code only the inviter gets, so nobody can make a link in someone else's name and become
# their friend (and so able to message them) by signing up through it. The key is kept in the data file.
def invite_code(d, h)
  d['invite_key'] ||= SecureRandom.hex(16)
  OpenSSL::HMAC.hexdigest('SHA256', d['invite_key'], "invite|#{h}")[0, 12]
end

def km_between(a, b, c, e)
  dy = (a - c) * 110.57; dx = (b - e) * 111.32 * Math.cos(a * Math::PI / 180)
  Math.hypot(dx, dy)
end

# ---------------------------------------------------------------------------------------------
# Analytics: first-party and small. Whitelisted event names, daily totals, and which days each account was active
# (for daily/weekly actives and 7-day retention). No content, no locations, no device ids. Kept in memory and
# written to data/stats.json once a minute so it never slows the app down.
TRACK_EVENTS = %w[open home_next home_tonight event_open event_share event_save event_invite event_chat notif_open
                  quests_open checkin quest_done saved_open invite_copy share_open sight_open sight_tell plan_save
                  scout_ask map_open search feed_open signup_ref push_on
                  mic_on mic_heard mic_none mic_err_audio mic_err_network mic_err_lang mic_err_service mic_err_denied mic_err_stuck mic_err_hear mic_err_other].freeze
STATS_FILE = File.join(__dir__, 'data', 'stats.json')
STATS = { lock: Mutex.new, d: (JSON.parse(File.read(STATS_FILE)) rescue nil) || {}, dirty: false }

def track!(name, h = nil)
  return unless TRACK_EVENTS.include?(name)
  day = Time.now.strftime('%Y-%m-%d')
  STATS[:lock].synchronize do
    s = STATS[:d]
    ((s['ev'] ||= {})[day] ||= Hash.new(0))[name] = s['ev'][day][name].to_i + 1
    STATS[:dirty] = true
  end
  active!(h) if h
end

def active!(h)
  day = Time.now.strftime('%Y-%m-%d')
  STATS[:lock].synchronize do
    days = ((STATS[:d]['active'] ||= {})[h] ||= [])
    next if days.last == day
    days << day; days.shift while days.size > 90
    STATS[:dirty] = true
  end
end

def stats_flush
  STATS[:lock].synchronize do
    next unless STATS[:dirty]
    s = STATS[:d]
    (s['ev'] || {}).keys.sort[0...-120].each { |k| s['ev'].delete(k) }
    FileUtils.mkdir_p(File.dirname(STATS_FILE))
    File.write("#{STATS_FILE}.tmp", JSON.generate(s))
    File.rename("#{STATS_FILE}.tmp", STATS_FILE)
    STATS[:dirty] = false
  end
end

def growth_report(d)
  today = Date.today
  days = (0..13).map { |i| (today - i).strftime('%Y-%m-%d') }.reverse
  act = STATS[:lock].synchronize { (STATS[:d]['active'] || {}).dup }
  ev = STATS[:lock].synchronize { (STATS[:d]['ev'] || {}).dup }
  dau = days.map { |day| act.count { |_h, ds| ds.include?(day) } }
  wau = act.count { |_h, ds| ds.any? { |x| x >= (today - 6).strftime('%Y-%m-%d') } }
  joined = d['users'].values.map { |u| [u['h'], (Date.parse(u['joined'].to_s) rescue nil)] }.select { |_, j| j }
  cohort = joined.select { |_, j| j <= today - 7 && j > today - 37 }
  kept = cohort.count { |h, j| (act[h] || []).any? { |x| x >= (j + 7).strftime('%Y-%m-%d') && x <= (j + 13).strftime('%Y-%m-%d') } }
  totals = Hash.new(0)
  ev.each { |day, m| m.each { |k, v| totals[k] += v.to_i } if day >= days.first }
  { days: days, dau: dau, wau: wau, users: d['users'].size,
    signups: days.map { |day| joined.count { |_, j| j.strftime('%Y-%m-%d') == day } },
    retention7: cohort.empty? ? nil : (kept * 100.0 / cohort.size).round, cohort: cohort.size,
    rsvps: d['rsvps'].values.sum { |m| m.size }, checkins: (d['quest'] || {}).values.sum { |q| q['checkins'].to_a.size },
    quests_done: (d['quest'] || {}).values.sum { |q| q['done'].to_h.size }, events: totals.sort_by { |_, v| -v }.to_h }
end

# ---------------------------------------------------------------------------------------------
# Share pages: a real page per event / sight / invite with Open Graph tags (so links unfurl in Messages,
# WhatsApp, Instagram DMs), which then opens the app on that item.
def share_page(title, desc, image, to)
  t = CGI.escapeHTML(title.to_s[0, 120]); s = CGI.escapeHTML(desc.to_s.gsub(/\s+/, ' ')[0, 280])
  img = image.to_s =~ %r{\Ahttps://} ? CGI.escapeHTML(image) : '/icon-512.png'
  <<~HTML
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>#{t} · Side Quest</title>
    <meta property="og:title" content="#{t}"><meta property="og:description" content="#{s}">
    <meta property="og:image" content="#{img}"><meta property="og:site_name" content="Side Quest">
    <meta name="twitter:card" content="summary_large_image"><meta name="theme-color" content="#070b18">
    <style>body{background:#070b18;color:#eef1fb;font:16px system-ui;display:grid;place-items:center;min-height:90vh;margin:0;text-align:center;padding:16px}
    a{color:#ff9a3c;font-weight:700}</style></head>
    <body><div><img src="/logo.png" alt="" width="64" height="64"><h1 style="font-size:22px">#{t}</h1><p style="color:#9aa3b8">#{s}</p>
    <p><a href="#{CGI.escapeHTML(to)}">Open in Side Quest →</a></p></div>
    <script>location.replace(#{JSON.generate(to)})</script></body></html>
  HTML
end

# ---------------------------------------------------------------------------------------------
# Event reminders: two hours before something you're going to starts (checked every 5 minutes).
def remind_due!
  evs = events_list
  return if evs.empty?
  t = now_ms
  soon = evs.select do |e|
    s = (Time.parse(e['start']).to_f * 1000 rescue nil)
    s && e['start'] !~ /T00:00(:00)?/ && s > t && s < t + 2 * 3_600_000
  end
  return if soon.empty?
  store do |d|
    done = (d['reminded'] ||= {})
    done.delete_if { |_k, at| at < t - 3 * 86_400_000 }
    soon.each do |e|
      (d['rsvps']["e:#{e['uid']}"] || {}).each do |h, st|
        next unless st == 'going' && !done["#{e['uid']}|#{h}"]
        done["#{e['uid']}|#{h}"] = t
        at = (Time.parse(e['start']).strftime('%-l:%M %p') rescue 'soon')
        notify!(d, h, 'remind', ref: "e:#{e['uid']}", text: "⏰ #{e['title'][0, 70]} starts at #{at}#{e['venue'] ? " · #{e['venue']}" : ''}")
      end
    end
  end
end

# Monday morning recap: what you did last week and a nudge toward the quest you're closest to finishing.
def weekly_recap!(force: false)
  t = Time.now
  return unless force || (t.monday? && t.hour.between?(9, 11))
  week = week_key(now_ms)
  last = week_key(now_ms - 7 * 86_400_000)
  store do |d|
    (d['quest'] || {}).each do |h, q|
      next unless d['users'][h] && (d['recap'] ||= {})[h] != week
      d['recap'][h] = week
      cs = q['checkins'].to_a.select { |c| week_key(c['at']) == last }
      evs = d['rsvps'].count { |id, m| m[h] == 'going' }
      next if cs.empty?
      prog = quest_progress(d, h)
      close = QUESTS.reject { |x| q['done'].to_h[x[:id]] }.map { |x| [x, x[:goal] - prog[x[:id]].to_i] }.select { |_, left| left > 0 }.min_by { |_, left| left }
      nudge = close ? " #{close[0][:e]} #{close[1]} more for #{close[0][:name]}!" : ''
      notify!(d, h, 'quest', ref: 'recap', text: "📅 Last week: #{cs.size} check-in#{cs.size == 1 ? '' : 's'}, #{evs} plan#{evs == 1 ? '' : 's'} on your list.#{nudge}")
    end
  end
end

def v2_background
  store { |d| d['invite_key'] ||= SecureRandom.hex(16) }   # made once and kept, so invite links keep working
  push_worker
  Thread.new do
    loop do
      sleep 60
      stats_flush rescue warn("[v2] stats: #{$!.message}")
      remind_due! rescue warn("[v2] reminders: #{$!.message}") if (Time.now.min % 5).zero?
      weekly_recap! rescue warn("[v2] recap: #{$!.message}") if Time.now.min == 7
    end
  end
  at_exit { stats_flush rescue nil }
end

# ---------------------------------------------------------------------------------------------
def mount_v2(server)
  # Notifications: the inbox, marking things read, and which kinds you want (mute).
  route(server, '/api/notifs') do |b, h|
    store(write: b['read'] || b.key?('mute') ? true : false) do |d|
      if b['mute'].is_a?(Array)
        d['users'][h]['mute'] = b['mute'].map(&:to_s) & %w[freq friend down going chat join tag like quest joined remind invite]
      end
      list = ((d['notifs'] ||= {})[h] ||= [])
      if b['read'] == 'all' then list.each { |n| n['read'] = true }
      elsif b['read'] then list.each { |n| n['read'] = true if n['id'] == b['read'] }
      end
      hidden = blocked_between(d, h)
      { notifs: list.reject { |n| hidden.include?(n['from']) }.last(60).reverse, unread: list.count { |n| !n['read'] },
        mute: d['users'][h]['mute'] || [] }
    end
  end

  # Quests: your progress, and friends on a leaderboard (only people who haven't opted out).
  route(server, '/api/quests', get: true) do |_b, h|
    store(write: false) do |d|
      board = ([h] + friends_of(d, h).to_a).select { |x| d['users'][x] && (x == h || !d['users'][x]['lb_hidden']) }
                                           .map { |x| q = (d['quest'] || {})[x] || {}; { h: x, xp: q['xp'].to_i, level: level_of(q['xp']), badges: (q['done'] || {}).size } }
                                           .sort_by { |r| -r[:xp] }.first(30)
      quest_view(d, h).merge(board: board, hidden: !!d['users'][h]['lb_hidden'], share: !!d['users'][h]['share_checkins'])
    end
  end
  route(server, '/api/quests/board') do |b, h|   # show or hide me on friends' leaderboards; share check-ins with friends
    store do |d|
      u = d['users'][h]
      u['lb_hidden'] = b['hidden'] == true if b.key?('hidden')
      u['share_checkins'] = b['share'] == true if b.key?('share')
      { ok: true, hidden: !!u['lb_hidden'], share: !!u['share_checkins'] }
    end
  end

  # Check in: the phone says where; we look the place up ourselves and count it once per place per day.
  route(server, '/api/checkin') do |b, h|
    limit!("checkin:#{h}", 40, 86_400)
    k = b['k'].to_s; id = b['id'].to_s
    raise 'Nothing to check in at.' unless %w[sight place area event].include?(k) && id =~ CHECKIN_RE
    tgt = checkin_target(k, id) or raise "That spot isn't in Side Quest."
    if tgt[:ev]   # an event counts while it's on (an hour either side)
      s = (Time.parse(tgt[:ev]['start']).to_f * 1000 rescue 0); e = (Time.parse(tgt[:ev]['end'].to_s).to_f * 1000 rescue s + 4 * 3_600_000)
      raise "You can check in while it's on." unless now_ms.between?(s - 3_600_000, [e, s + 3_600_000].max + 3_600_000)
    end
    hr = Time.now.hour
    tags = tgt[:tags] + (hr >= 23 || hr < 4 ? %w[late] : [])
    zone = Places::HOTSPOTS.find { |z| km_between(z[:lat], z[:lng], tgt[:lat], tgt[:lng]) * 1000 < z[:r].to_f + 60 }
    store do |d|
      q = quest_rec(d, h)
      today = Time.now.strftime('%Y-%m-%d')
      if q['checkins'].any? { |c| c['k'] == k && c['id'] == id && Time.at(c['at'] / 1000).strftime('%Y-%m-%d') == today }
        next { ok: true, again: true, name: tgt[:name] }.merge(quest_view(d, h))
      end
      before = q['done'].keys
      q['checkins'] << { 'k' => k, 'id' => id, 'name' => tgt[:name].to_s[0, 80], 'tags' => tags, 'zone' => zone && zone[:id], 'at' => now_ms }
      remember_taste!(d, h, 'checkin', k, id) unless k == 'area'
      q['checkins'].shift while q['checkins'].size > 500
      q['xp'] += CHECKIN_XP
      quest_award!(d, h)
      track!('checkin', h)
      newly = (q['done'].keys - before).map { |qid| QUESTS.find { |x| x[:id] == qid } }
      newly.each { track!('quest_done') }
      gain = CHECKIN_XP + newly.sum { |x| featured_quest[:id] == x[:id] ? (x[:xp] * 1.5).round : x[:xp] }
      { ok: true, name: tgt[:name], xp_gain: gain, completed: newly }.merge(quest_view(d, h))
    end
  end

  # Saved: events, places and sights, yours only.
  route(server, '/api/saves') do |b, h|
    limit!("saves:#{h}", 300, 3600)
    store(write: !!b['action']) do |d|
      list = ((d['saves'] ||= {})[h] ||= [])
      k, id = b['k'].to_s, b['id'].to_s
      case b['action']
      when 'add'
        raise 'Bad item.' unless %w[event place sight].include?(k) && id =~ CHECKIN_RE
        list.reject! { |x| x['k'] == k && x['id'] == id }
        list << { 'k' => k, 'id' => id, 'name' => b['name'].to_s[0, 100], 'at' => now_ms }
        list.shift while list.size > 200
        remember_taste!(d, h, 'save', k, id)
        track!('event_save', h) if k == 'event'
      when 'remove'
        list.reject! { |x| x['k'] == k && x['id'] == id }
        forget_taste!(d, h, k == 'event' && id !~ /\Ae:/ ? "e:#{id}" : id, %w[save])
      end
      { saves: list.reverse }
    end
  end

  # Event discussion: anyone signed in can read; posting is screened like any other post. Replies notify the
  # people who already talked there.
  route(server, '/api/event/chat') do |b, h|
    ev = b['id'].to_s[0, 40]
    raise 'No event.' unless ev =~ /\Ae:[0-9a-f]{6,32}\z/
    text = b['text'].to_s.strip[0, 400]
    unless text.empty?
      limit!("evchat:#{h}", 30, 3600)
      flagged = !moderate(text)
    end
    store(write: !text.empty?) do |d|
      th = ((d['ev_chat'] ||= {})[ev] ||= [])
      unless text.empty?
        th << { 'id' => "c#{SecureRandom.hex(5)}", 'u' => h, 't' => text, 'at' => now_ms, 'unreviewed' => flagged }
        th.shift while th.size > 200
        title = event_title(ev)
        (th.map { |m| m['u'] } + (d['rsvps'][ev] || {}).select { |_x, st| st == 'going' }.keys).uniq.first(30).each do |x|
          notify!(d, x, 'chat', from: h, ref: ev, text: "💬 @#{h} on #{title.empty? ? 'an event you follow' : title}: #{text[0, 70]}")
        end
        track!('event_chat', h)
      end
      hidden = blocked_between(d, h)
      { msgs: th.reject { |m| hidden.include?(m['u']) || m['removed'] }.last(80) }
    end
  end

  # Group chat: members only (checked here), same screening and storage as event chats, kept under "g:<id>".
  route(server, '/api/group/chat') do |b, h|
    gid = b['id'].to_s[0, 20]
    text = b['text'].to_s.strip[0, 400]
    member = store(write: false) { |d| d['groups'][gid] && !d['groups'][gid]['removed'] && (d['members'][gid] || []).include?(h) }
    raise Forbidden, 'Join the group to see and join its chat.' unless member
    unless text.empty?
      limit!("gchat:#{h}", 60, 3600)
      flagged = !moderate(text)
    end
    store(write: !text.empty?) do |d|
      th = ((d['ev_chat'] ||= {})["g:#{gid}"] ||= [])
      unless text.empty?
        th << { 'id' => "c#{SecureRandom.hex(5)}", 'u' => h, 't' => text, 'at' => now_ms, 'unreviewed' => flagged }
        th.shift while th.size > 300
        (th.map { |m| m['u'] }.uniq & (d['members'][gid] || [])).first(40).each do |x|
          notify!(d, x, 'chat', from: h, ref: "g:#{gid}", text: "💬 @#{h} in #{d['groups'][gid]['n'].to_s[0, 40]}: #{text[0, 70]}")
        end
      end
      hidden = blocked_between(d, h)
      { msgs: th.reject { |m| hidden.include?(m['u']) || m['removed'] }.last(80) }
    end
  end

  # Invite a friend to an event: a DM with the link (friends only, like any DM).
  route(server, '/api/event/invite') do |b, h|
    limit!("evinvite:#{h}", 60, 3600)
    ev = b['id'].to_s[0, 40]
    raise 'No event.' unless ev =~ /\Ae:[0-9a-f]{6,32}\z/
    title = event_title(ev)
    raise "That event isn't listed anymore." if title.empty?
    to = Array(b['to']).map(&:to_s).uniq.first(20)
    store do |d|
      ok = to.select { |x| d['users'][x] && friends_of(d, h).include?(x) && !blocked_between(d, h).include?(x) }
      ok.each do |x|
        thread = (d['dms'][dm_key(h, x)] ||= [])
        thread << { 'f' => h, 't' => "🎟️ Come with me? #{title} → /e/#{ev.sub('e:', '')}", 'at' => now_ms, 'ev' => ev }
        thread.shift while thread.size > 500
        notify!(d, x, 'invite', from: h, ref: ev, text: "🎟️ @#{h} invited you to #{title}")
      end
      track!('event_invite', h)
      { ok: true, sent: ok.size }
    end
  end

  # Phone notifications: save / forget this device's push subscription.
  route(server, '/api/push') do |b, h|
    limit!("push:#{h}", 30, 3600)
    sub = b['sub']
    store do |d|
      list = ((d['push'] ||= {})[h] ||= [])
      if b['action'] == 'off'
        list.reject! { |x| x['endpoint'] == (sub.is_a?(Hash) ? sub['endpoint'] : b['endpoint']).to_s }
      else
        raise 'That browser gave an address Side Quest does not send to.' unless WebPush.valid_sub?(sub)
        list.reject! { |x| x['endpoint'] == sub['endpoint'] }
        list << { 'endpoint' => sub['endpoint'].to_s[0, 800], 'keys' => { 'p256dh' => sub['keys']['p256dh'].to_s[0, 200], 'auth' => sub['keys']['auth'].to_s[0, 60] }, 'at' => now_ms }
        list.shift while list.size > 5
        track!('push_on', h)
      end
      { ok: true, devices: list.size }
    end
  end

  # Analytics beacons (guests too: counted, never tied to anyone).
  route(server, '/api/t', auth: false) do |b, h, req|
    limit!("t:#{h || client_ip(req)}", 600, 3600)
    track!(b['e'].to_s, h)
    { ok: true }
  end
  server.mount_proc('/api/admin/growth') do |req, res|
    res['Content-Type'] = 'application/json'; res['Cache-Control'] = 'no-store'
    if admin_ok?(req) then res.body = JSON.generate(store(write: false) { |d| growth_report(d) })
    else res.status = 403; res.body = JSON.generate(error: 'Wrong admin token.')
    end
  end

  # Share pages
  server.mount_proc('/e') do |req, res|
    uid = req.path[%r{\A/e/([0-9a-f]{6,32})\z}, 1]
    e = uid && event_by_uid(uid)
    res['Content-Type'] = 'text/html; charset=utf-8'
    next (res.status = 404; res.body = share_page('Event not found', 'It may have ended.', nil, '/')) unless e
    when_s = (Time.parse(e['start']).strftime('%a %b %-d, %-l:%M %p') rescue '')
    res.body = share_page(e['title'], [when_s, e['venue'], e['description']].compact.join(' · '), e['image'], "/?ev=#{uid}")
  end
  server.mount_proc('/s') do |req, res|
    id = req.path[%r{\A/s/([A-Za-z0-9_.-]{1,40})\z}, 1]
    s = id && Sights.find(id)
    res['Content-Type'] = 'text/html; charset=utf-8'
    next (res.status = 404; res.body = share_page('Not found', '', nil, '/')) unless s
    res.body = share_page(s['name'], s['text'] || s['what'] || 'A sight in Austin', s['photo'], "/?sight=#{id}")
  end
  server.mount_proc('/i') do |req, res|
    h, code = req.path.match(%r{\A/i/([a-z0-9_]{3,20})(?:/([0-9a-f]{12}))?\z})&.captures
    known = h && store(write: false) { |d| !!d['users'][h] }
    res['Content-Type'] = 'text/html; charset=utf-8'
    res.body = share_page(known ? "@#{h} invited you to Side Quest" : 'Side Quest',
                          "What's the move tonight, and who's coming? Real Austin events, friends, food, history and quests.",
                          nil, known ? "/?ref=#{h}#{code ? "&rk=#{code}" : ''}" : '/')
  end
end

# ---------------------------------------------------------------------------------------------
# Live safety on the server (V1 screened viewer requests and stream titles only in the browser):
# - a request reaches the streamer only with a pass from /api/screen (signed, 10 minutes, tied to the person and the
#   exact words), and the hard rules are applied here too;
# - a stream title shows only once it's been checked (until then viewers see "Live");
# - an accepted "visit" request doesn't reveal where the streamer is heading while their location delay is on.
LIVE_HARD_NO = /\b(their|his|her|someone'?s) (home|house|apartment|car)\b|\b(where (he|she|they) lives?|address|follow (him|her|them|that|this)|stalk|dox|trespass|break in|fight|punch|steal|chug|naked|nude|jump off|rooftop|highway|weapon|gun|knife)\b/i
SCREEN_PASS_KEY = SecureRandom.bytes(32)

def screen_mac(h, exp, text)
  OpenSSL::HMAC.hexdigest('SHA256', SCREEN_PASS_KEY, "#{h}|#{exp}|#{Digest::SHA256.hexdigest(text.to_s.strip)}")
end
def screen_pass(h, text) exp = Time.now.to_i + 600; "#{exp}.#{screen_mac(h, exp, text)}" end
def screen_pass_ok?(h, text, pass)
  exp, mac = pass.to_s.split('.')
  exp.to_i > Time.now.to_i && mac && secure_compare(screen_mac(h, exp.to_i, text), mac)
end

# nil when the request may go out, else why not
def live_request_problem(h, r)
  return 'bad request' unless r.is_a?(Hash)
  text = r['text'].to_s
  return 'Requests are 240 characters at most.' if text.strip.empty? || text.size > 240
  return 'Not sent: it could put someone at risk or send the streamer somewhere private.' if text =~ LIVE_HARD_NO
  return 'Requests are checked for safety first. Try sending it again.' if MODERATE && !screen_pass_ok?(h, text, r['pass'])
  nil
end

LIVE_TITLES = { lock: Mutex.new, seen: {} }   # "h|title" => :ok / :no / :pending
def live_title(h, title)
  title = title.to_s[0, 70]
  return title if title.strip.empty?
  key = "#{h}|#{title}"
  state = LIVE_TITLES[:lock].synchronize { LIVE_TITLES[:seen][key] }
  unless state
    local_ok = title !~ LIVE_HARD_NO && title !~ /(\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4}/ && title !~ /[\w.+-]+@[\w-]+\.[\w.]+/
    state = !local_ok ? :no : MODERATE ? :pending : :ok
    LIVE_TITLES[:lock].synchronize { LIVE_TITLES[:seen].shift while LIVE_TITLES[:seen].size > 2000; LIVE_TITLES[:seen][key] = state }
    if state == :pending
      Thread.new do
        ok = begin
          moderate(title)
          true
        rescue Forbidden
          false
        rescue StandardError
          true   # unreachable = allowed, like posts
        end
        LIVE_TITLES[:lock].synchronize { LIVE_TITLES[:seen][key] = ok ? :ok : :no }
      end
    end
  end
  state == :ok ? title : 'Live'
end

def live_sanitize!(s)
  s['title'] = live_title(s['u'], s['title'])
  return unless s['delay'].to_i > 0 && s['reqs'].is_a?(Array)
  s['reqs'].each do |r|
    next unless r.is_a?(Hash) && r['kind'] == 'visit' && %w[accepted done].include?(r['status'])
    r['place'] = nil; r['placeHidden'] = true
  end
end
