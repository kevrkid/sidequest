# Rewards on top of quests (v2.rb): 🪙 coins kept here (never on the phone), a daily streak, a weekly Austin
# challenge, and leaderboards (friends / Austin this week / all time). Coins come from doing real things and are spent
# in the app: boost a post, a profile frame, tips to streamers. Everything is in d['quest'][h]:
#   'coins', 'wk' => { "2026-43" => xp that week }, 'days' => ["2026-10-24", ...] (days you did something),
#   'earn' => { "<kind>:<day>" => times } (daily caps), 'frames' => [...], 'frame', 'wch' => { week => true }.
require 'date'

COIN_FOR = { 'checkin' => 5, 'post' => 3, 'story' => 2, 'flare' => 2, 'plan' => 5, 'recruit' => 25, 'streak' => 2 }.freeze
COIN_CAP = { 'post' => 5, 'story' => 3, 'flare' => 3, 'plan' => 2, 'checkin' => 12 }.freeze   # per day
FRAMES = { 'gold' => ['🥇 Gold', 150], 'neon' => ['💜 Neon', 120], 'fire' => ['🔥 Fire', 200], 'leaf' => ['🌿 Greenbelt', 100], 'disco' => ['🪩 Disco', 250] }.freeze
BOOST_COST = 40
BOOST_MS = 6 * 3_600_000
WEEKLY = [
  { id: 'coffee', e: '☕', name: 'Coffee crawl', desc: 'Check in at 3 different coffee shops or bakeries', goal: 3, coins: 60 },
  { id: 'outside', e: '🌳', name: 'Get outside', desc: 'Check in at 3 parks, lakes or trails', goal: 3, coins: 60 },
  { id: 'shows', e: '🎸', name: 'See a show', desc: 'Check in at 2 events', goal: 2, coins: 70 },
  { id: 'posts', e: '📝', name: 'Share the week', desc: 'Post 3 public posts with a place', goal: 3, coins: 50 },
  { id: 'plans', e: '🗳️', name: 'Make it happen', desc: 'Lock in a plan with friends', goal: 1, coins: 60 },
  { id: 'explore', e: '🧭', name: 'New ground', desc: 'Check in at 4 places you have never been', goal: 4, coins: 80 }
].freeze

def this_week(t = Time.now) t.strftime('%G-%V') end
def weekly_challenge(t = Time.now) WEEKLY[t.strftime('%V').to_i % WEEKLY.size] end

# XP goes through here so the weekly board knows what you earned this week.
def xp_add!(d, h, n)
  q = quest_rec(d, h)
  q['xp'] += n
  wk = (q['wk'] ||= {})
  wk[this_week] = wk[this_week].to_i + n
  wk.delete(wk.keys.min) while wk.size > 12
end

def coins_add!(d, h, n, why = nil)
  return 0 unless d['users'][h] && n.positive?
  q = quest_rec(d, h)
  if why && COIN_CAP[why]
    k = "#{why}:#{Time.now.strftime('%F')}"
    e = (q['earn'] ||= {})
    return 0 if e[k].to_i >= COIN_CAP[why]
    e[k] = e[k].to_i + 1
    e.delete_if { |kk, _| kk.split(':').last < (Time.now - 3 * 86_400).strftime('%F') }
  end
  q['coins'] = q['coins'].to_i + n
  n
end

# Something real happened today (a check-in, a post, a story, a flare, a plan): it counts for the daily streak,
# and pays a little coin. Then the weekly challenge is checked.
def did_something!(d, h, kind)
  return unless d['users'][h]
  q = quest_rec(d, h)
  days = (q['days'] ||= [])
  today = Time.now.strftime('%F')
  unless days.include?(today)
    days << today
    days.shift while days.size > 60
    s = day_streak(q)
    coins_add!(d, h, COIN_FOR['streak'] * [s, 10].min) if s >= 2   # longer streaks pay more (up to 20 a day)
    notify!(d, h, 'quest', ref: 'streak', text: "🔥 #{s}-day streak! Keep it going tomorrow.") if [3, 7, 14, 30].include?(s)
  end
  coins_add!(d, h, COIN_FOR[kind], kind) if COIN_FOR[kind]
  weekly_check!(d, h)
end

def day_streak(q)
  days = (q['days'] || []).sort.reverse
  return 0 if days.empty?
  t = Date.today
  return 0 unless [t.to_s, (t - 1).to_s].include?(days[0])
  n = 0; cur = Date.parse(days[0])
  days.each { |x| break unless x == cur.to_s; n += 1; cur -= 1 }
  n
end

def weekly_progress(d, h, ch = weekly_challenge)
  q = quest_rec(d, h)
  wk = this_week
  mine = q['checkins'].select { |c| week_key(c['at']) == wk }
  case ch[:id]
  when 'coffee' then mine.select { |c| c['k'] == 'place' && (Places.find(c['id']) || {})['kind'].to_s =~ /cafe|bakery/ }.map { |c| c['id'] }.uniq.size
  when 'outside' then mine.count { |c| (c['tags'] || []).include?('outdoors') }
  when 'shows' then mine.count { |c| c['k'] == 'event' }
  when 'posts' then (d['wall'] || []).count { |p| p['u'] == h && !p['removed'] && p['place'] && week_key(p['at']) == wk }
  when 'plans' then (d['chats'] || {}).values.count { |c| c.dig('plan', 'by') == h && c.dig('plan', 'status') == 'set' && week_key(c['plan']['at'].to_i) == wk }
  when 'explore'
    before = q['checkins'].reject { |c| week_key(c['at']) == wk }.map { |c| c['id'] }
    mine.map { |c| c['id'] }.uniq.count { |id| !before.include?(id) }
  else 0
  end
end

def weekly_check!(d, h)
  q = quest_rec(d, h)
  ch = weekly_challenge
  key = "#{this_week}:#{ch[:id]}"
  return if (q['wch'] ||= {})[key] || weekly_progress(d, h, ch) < ch[:goal]
  q['wch'][key] = now_ms
  q['wch'].delete(q['wch'].keys.min) while q['wch'].size > 20
  coins_add!(d, h, ch[:coins])
  xp_add!(d, h, 100)
  notify!(d, h, 'quest', ref: 'weekly', text: "#{ch[:e]} Weekly challenge done: #{ch[:name]} (+#{ch[:coins]} 🪙, +100 XP)")
end

def frame_of(d, h) ((d['quest'] || {})[h] || {})['frame'] end

def rewards_view(d, h)
  q = quest_rec(d, h)
  ch = weekly_challenge
  { coins: q['coins'].to_i, day_streak: day_streak(q), week_xp: (q['wk'] || {})[this_week].to_i,
    weekly: ch.merge(have: [weekly_progress(d, h, ch), ch[:goal]].min, done: !!(q['wch'] || {})["#{this_week}:#{ch[:id]}"],
                     ends: (Date.today + (8 - Date.today.cwday)).to_s),
    frames: FRAMES.map { |k, (l, c)| { id: k, label: l, cost: c, owned: (q['frames'] || []).include?(k) } }, frame: q['frame'],
    earn: COIN_FOR, boost_cost: BOOST_COST }
end

def mount_rewards(server)
  # Leaderboards: friends (all time), Austin this week, Austin all time. People who hid themselves aren't on any.
  route(server, '/api/leaderboard', get: true) do |_b, h, req|
    scope = %w[friends week all].include?(req.query['scope']) ? req.query['scope'] : 'week'
    store(write: false) do |d|
      hidden = blocked_between(d, h)
      pool = scope == 'friends' ? [h] + friends_of(d, h).to_a : d['users'].keys
      wk = this_week
      rows = pool.uniq.select { |x| d['users'][x] && !d['users'][x]['banned'] && !hidden.include?(x) && (x == h || !d['users'][x]['lb_hidden']) }.map do |x|
        q = (d['quest'] || {})[x] || {}
        { h: x, xp: scope == 'week' ? (q['wk'] || {})[wk].to_i : q['xp'].to_i, level: level_of(q['xp']), streak: day_streak(q), frame: q['frame'] }.compact
      end
      rows = rows.select { |r| scope == 'friends' || r[:xp].positive? || r[:h] == h }.sort_by { |r| [-r[:xp], r[:h]] }   # friends: everyone, even at 0
      me = rows.index { |r| r[:h] == h }
      { scope: scope, rows: rows.first(50), me: me && rows[me].merge(rank: me + 1), total: rows.size }
    end
  end

  route(server, '/api/rewards', get: true) do |_b, h|
    store(write: false) { |d| rewards_view(d, h) }
  end

  # Spend: a profile frame (buy once, wear any you own, or none); tips are in /api/coins/tip.
  route(server, '/api/rewards/frame') do |b, h|
    store do |d|
      q = quest_rec(d, h)
      id = b['id'].to_s
      own = (q['frames'] ||= [])
      if id.empty?
        q.delete('frame')
      else
        f = FRAMES[id] or raise 'No such frame.'
        unless own.include?(id)
          raise "You need #{f[1]} 🪙 for that (you have #{q['coins'].to_i})." if q['coins'].to_i < f[1]
          q['coins'] -= f[1]
          own << id
        end
        q['frame'] = id
      end
      rewards_view(d, h)
    end
  end

  # Coins as live-stream tips: held when you send the request, paid to the streamer when they do it, back to you if not.
  route(server, '/api/coins/tip') do |b, h|
    limit!("tip:#{h}", 120, 3600)
    store do |d|
      holds = (d['coin_holds'] ||= {})
      ref = b['ref'].to_s[0, 40]
      raise 'bad tip' if ref.empty?
      q = quest_rec(d, h)
      case b['do']
      when 'hold'
        n = b['n'].to_i
        raise 'bad tip' unless n.between?(1, 1000)
        raise "You only have #{q['coins'].to_i} 🪙." if q['coins'].to_i < n
        raise 'Already sent.' if holds[ref]
        q['coins'] -= n
        holds[ref] = { 'from' => h, 'n' => n, 'to' => b['to'].to_s[0, 20], 'at' => now_ms }
      when 'pay', 'refund'
        x = holds[ref] or raise 'No such tip.'
        raise Forbidden, 'Not your tip.' unless x['from'] == h
        holds.delete(ref)
        b['do'] == 'pay' && d['users'][x['to']] ? coins_add!(d, x['to'], x['n']) : coins_add!(d, h, x['n'])
      else raise 'bad action'
      end
      holds.delete_if { |_, x| x['at'] < now_ms - 2 * 86_400_000 && (coins_add!(d, x['from'], x['n']) || true) }   # unclaimed: back after 2 days
      { ok: true, coins: q['coins'].to_i }
    end
  end
end
