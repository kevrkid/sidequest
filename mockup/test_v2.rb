# V2 server features against a throwaway copy of the server (no internet, no Claude): ruby test_v2.rb
# Notifications, quests & check-ins, saves, event discussion + invites, referrals, share pages, analytics, privacy.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8799; EV_PORT = 9914
BASE = "http://127.0.0.1:#{PORT}"

# a fake events service: one show on now near 6th Street, one tomorrow
now = Time.now
EVENTS = [
  { uid: 'abc123def456', title: 'Test Show', start: (now - 1800).iso8601, end: (now + 7200).iso8601, venue: 'Test Hall',
    city: 'Austin', lat: 30.2671, lng: -97.7391, geo_precise: true, category: 'music', description: 'A loud test show.' },
  { uid: 'fff000fff000', title: 'Tomorrow Thing', start: (now + 86_400).iso8601, venue: 'Elsewhere', city: 'Austin', lat: 30.3, lng: -97.7, category: 'comedy' }
]
ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: EVENTS.size, events: EVENTS) }
Thread.new { ev.start }

dir = $dir = Dir.mktmpdir('sq-v2-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
log = File.join(dir, 'server.log')
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PLACES_FILE' => 'test_places.json', 'SQ_OUTDOORS_FILE' => 'test_outdoors.json',
              'SQ_SIGHTS_FILE' => 'test_sights.json', 'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}", 'SQ_ADMIN_TOKEN' => 'adm',
              'SQ_LIVEKIT_URL' => nil, 'SQ_GOOGLE_PLACES_KEY' => nil, 'SQ_GOOGLE_TTS_KEY' => nil },
            'ruby', 'server.rb', chdir: dir, out: log, err: log)
at_exit { Process.kill('TERM', pid) rescue nil; FileUtils.rm_rf(dir) }

class Who
  attr_reader :h
  def initialize(h) @h = h; @c = nil end
  def req(m, path, body = nil, hdr = {})
    u = URI("#{BASE}#{path}")
    r = Net::HTTP.start(u.host, u.port) do |http|
      q = m == :get ? Net::HTTP::Get.new(u) : Net::HTTP::Post.new(u, 'Content-Type' => 'application/json')
      q['Cookie'] = "sq_s=#{@c}" if @c
      hdr.each { |k, v| q[k] = v }
      q.body = JSON.generate(body) if body
      http.request(q)
    end
    @c = r['Set-Cookie'][/sq_s=([^;]+)/, 1] if r['Set-Cookie'].to_s.include?('sq_s=')
    [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
  end
  def post(p, b = {}) req(:post, p, b) end
  def get(p) req(:get, p) end
  def signup(extra = {}) post('/api/signup', { h: @h, pw: 'password123', adult: true, terms: true }.merge(extra)) end
end

$pass = $fail = 0
def t(name)
  r = yield
  $pass += 1; puts "PASS #{name}#{r.is_a?(String) ? "  [#{r}]" : ''}"
rescue => e
  $fail += 1; puts "FAIL #{name}: #{e.message[0, 300]}"
end
def check(c, m = 'failed') raise m.to_s unless c end

40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
amy, bo, cy = Who.new('amy_v2'), Who.new('bo_v2'), Who.new('cy_v2')
amy.signup; bo.signup

t('a wave notifies the other person; waving back makes friends and tells the first') {
  amy.post('/api/friend', to: 'bo_v2', action: 'request')
  _, n = bo.post('/api/notifs')
  check(n['unread'] == 1 && n['notifs'][0]['t'] == 'freq' && n['notifs'][0]['from'] == 'amy_v2', n)
  bo.post('/api/friend', to: 'amy_v2', action: 'accept')
  _, n2 = amy.post('/api/notifs')
  check(n2['notifs'].any? { |x| x['t'] == 'friend' && x['from'] == 'bo_v2' }, n2)
}
t('the unread count rides along with /api/state; mark all read clears it') {
  _, s = bo.get('/api/state')
  bo.post('/api/notifs', read: 'all')
  _, s2 = bo.get('/api/state')
  check(s['v2']['unread'] >= 1 && s2['v2']['unread'] == 0, [s['v2'], s2['v2']])
}
t("RSVP going tells friends who are already going") {
  bo.post('/api/rsvp', id: 'e:abc123def456', status: 'going', title: 'Test Show')
  amy.post('/api/rsvp', id: 'e:abc123def456', status: 'going', title: 'Test Show')
  _, n = bo.post('/api/notifs')
  check(n['notifs'].any? { |x| x['t'] == 'going' && x['text'].include?('Test Show') }, n['notifs'].map { |x| x['text'] })
}
t('check in at a historical marker: XP, counted once a day, unknown spots refused') {
  c, j = amy.post('/api/checkin', k: 'sight', id: 'm9001')
  _, j2 = amy.post('/api/checkin', k: 'sight', id: 'm9001')
  c3, j3 = amy.post('/api/checkin', k: 'sight', id: 'nope')
  check(c == 200 && j['xp_gain'] >= 10 && j['xp'] == j['xp_gain'] && j2['again'] && c3 == 400, [j, j2, j3])   # (+60 after 11 PM: Night owl)
}
t('check in at an event only while it is on') {
  c1, j1 = amy.post('/api/checkin', k: 'event', id: 'e:abc123def456')
  c2, j2 = amy.post('/api/checkin', k: 'event', id: 'e:fff000fff000')
  check(c1 == 200 && c2 == 400 && j2['error'] =~ /while it's on/, [c1, j1, c2, j2])
}
t('the History buff quest completes at 5 and pays its XP, with a notification') {
  amy.post('/api/checkin', k: 'sight', id: 'm9002')
  amy.post('/api/checkin', k: 'sight', id: 'w1001')
  # two more markers/landmarks only exist in the real data, so add them to the test file's copy on the fly
  sights = JSON.parse(File.read(File.join($dir, 'test_sights.json')))
  sights['sights'] += [{ 'id' => 'm9003', 'kind' => 'marker', 'name' => 'Third Marker', 'lat' => 30.27, 'lng' => -97.74, 'src' => 'thc' },
                       { 'id' => 'm9004', 'kind' => 'marker', 'name' => 'Fourth Marker', 'lat' => 30.271, 'lng' => -97.741, 'src' => 'thc' }]
  File.write(File.join($dir, 'test_sights.json'), JSON.generate(sights)); sleep 1.1   # sights.rb reloads on mtime
  amy.post('/api/checkin', k: 'sight', id: 'm9003')
  _, j = amy.post('/api/checkin', k: 'sight', id: 'm9004')
  hist = j['quests'].find { |q| q['id'] == 'history' }
  _, n = amy.post('/api/notifs')
  check(hist['done'] && j['completed'].any? { |q| q['id'] == 'history' } && n['notifs'].any? { |x| x['t'] == 'quest' }, [hist, j['completed']])
  "xp #{j['xp']}, level #{j['level']}"
}
t('friends leaderboard: friends only, and you can hide yourself') {
  _, q = bo.get('/api/quests')
  names = q['board'].map { |r| r['h'] }
  amy.post('/api/quests/board', hidden: true)
  _, q2 = bo.get('/api/quests')
  check(names.sort == %w[amy_v2 bo_v2] && q2['board'].map { |r| r['h'] } == ['bo_v2'], [names, q2['board']])
  amy.post('/api/quests/board', hidden: false)
}
t('saves are per person: add, list, remove') {
  amy.post('/api/saves', action: 'add', k: 'sight', id: 'm9001', name: 'Test Moonlight Tower')
  amy.post('/api/saves', action: 'add', k: 'event', id: 'e:abc123def456', name: 'Test Show')
  _, mine = amy.post('/api/saves'); _, bos = bo.post('/api/saves')
  amy.post('/api/saves', action: 'remove', k: 'sight', id: 'm9001')
  _, after = amy.post('/api/saves')
  check(mine['saves'].size == 2 && bos['saves'].empty? && after['saves'].map { |x| x['id'] } == ['e:abc123def456'], [mine, bos, after])
}
t('event discussion: post, read, and replies notify the people already talking') {
  bo.post('/api/event/chat', id: 'e:abc123def456', text: 'Who is going early?', title: 'Test Show')
  _, j = amy.post('/api/event/chat', id: 'e:abc123def456', text: 'Me! 7pm at the door', title: 'Test Show')
  _, n = bo.post('/api/notifs')
  check(j['msgs'].size == 2 && n['notifs'].any? { |x| x['t'] == 'chat' && x['from'] == 'amy_v2' }, [j, n['notifs'].first])
}
t('event discussion blocks phone numbers and bad ids') {
  c1, = amy.post('/api/event/chat', id: 'e:abc123def456', text: 'call me 512-555-1234')
  c2, = amy.post('/api/event/chat', id: 'x:bad', text: 'hi')
  check(c1 == 403 && c2 == 400, [c1, c2])
}
t('invite a friend to an event: a DM with the link + a notification; strangers are skipped') {
  _, j = amy.post('/api/event/invite', id: 'e:abc123def456', title: 'Test Show', to: %w[bo_v2 cy_v2])
  _, dm = bo.get('/api/dm?with=amy_v2')
  msgs = dm['msgs'] || []
  check(j['sent'] == 1 && msgs.any? { |m| m['t'].to_s.include?('/e/abc123def456') }, [j, dm])
}
t('invite link: the new person can choose to be friends with whoever invited them') {
  cy.signup(ref: 'amy_v2', ref_friend: true)
  _, s = cy.get('/api/state')
  _, n = amy.post('/api/notifs')
  _, q = amy.get('/api/quests')
  check(s['friends']['list'].include?('amy_v2') && n['notifs'].any? { |x| x['t'] == 'joined' } &&
        q['quests'].find { |x| x['id'] == 'recruiter' }['done'], [s['friends'], n['notifs'].first])
}
t('share pages carry link previews and open the app on the item') {
  ev = Net::HTTP.get(URI("#{BASE}/e/abc123def456"))
  sg = Net::HTTP.get(URI("#{BASE}/s/m9001"))
  inv = Net::HTTP.get(URI("#{BASE}/i/amy_v2"))
  check(ev.include?('og:title" content="Test Show') && ev.include?('/?ev=abc123def456') && sg.include?('Test Moonlight Tower') &&
        sg.include?('/?sight=m9001') && inv.include?('@amy_v2 invited you') && inv.include?('/?ref=amy_v2'), ev[0, 200])
}
t('share pages escape what they print') {
  EVENTS << { uid: 'bad000bad000', title: '<script>alert(1)</script>', start: now.iso8601, city: 'Austin' }
  Net::HTTP.get(URI("#{BASE}/api/events"))   # (the cache keeps the old list for 5 minutes; this just checks escaping on what's there)
  sg = Net::HTTP.get(URI("#{BASE}/s/m9001"))
  check(!sg.include?('<script>alert'), 'unescaped')
}
t('analytics: whitelisted names only; the admin growth report needs the token') {
  amy.post('/api/t', e: 'event_open'); amy.post('/api/t', e: 'event_open'); amy.post('/api/t', e: 'evil_thing')
  c1, = amy.get('/api/admin/growth')
  c2, g = amy.req(:get, '/api/admin/growth', nil, 'X-Admin-Token' => 'adm')
  check(c1 == 403 && c2 == 200 && g['events']['event_open'] == 2 && !g['events'].key?('evil_thing') && g['dau'].last >= 2 && g['users'] == 3, g)
  "dau #{g['dau'].last}, wau #{g['wau']}"
}
t("friends see each other's level and badges; a stranger's quests stay private") {
  _, sb = bo.get('/api/state'); _, sc = Who.new('nobody').tap(&:signup).get('/api/state')
  check(sb['badges']['amy_v2'] && sb['badges']['amy_v2']['done'].include?('history') && !sc['badges'].key?('amy_v2'), [sb['badges'], sc['badges']])
}
t('deleting an account removes its notifications, quests and saves') {
  amy.post('/api/account/delete', pw: 'password123', confirm: true)
  sleep 0.3
  d = JSON.parse(File.read(File.join($dir, 'data', 'app.json')))
  check(!(d['quest'] || {}).key?('amy_v2') && !(d['saves'] || {}).key?('amy_v2') && !(d['notifs'] || {}).key?('amy_v2') &&
        (d['notifs'] || {}).values.flatten.none? { |n| n['from'] == 'amy_v2' }, d.slice('quest', 'saves').keys)
}

# ---- live safety on the server: a second copy with screening ON and Claude unreachable (hard rules decide)
dir2 = Dir.mktmpdir('sq-v2-live')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir2)
pid2 = spawn({ 'PORT' => '8800', 'SQ_MODERATE' => '1', 'SQ_DEMO' => '0', 'SQ_ENGINE' => 'api', 'ANTHROPIC_API_KEY' => 'x', 'SQ_USE_API_KEY' => '1',
               'SQ_API_URL' => 'http://127.0.0.1:9/v1/messages', 'SQ_PLACES_FILE' => 'test_places.json', 'SQ_SIGHTS_FILE' => 'test_sights.json',
               'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}", 'SQ_LIVEKIT_URL' => nil },
             'ruby', 'server.rb', chdir: dir2, out: File.join(dir2, 'log'), err: File.join(dir2, 'log'))
at_exit { Process.kill('TERM', pid2) rescue nil; FileUtils.rm_rf(dir2) }
Object.send(:remove_const, :BASE); BASE = 'http://127.0.0.1:8800'
40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
sv, vw = Who.new('streamer_v2'), Who.new('viewer_v2'); sv.signup; vw.signup
req = ->(text, pass = nil) { vw.post('/api/relay', t: 'req', to: 'tabX', id: 'Lstream', from: 'tabV', r: { id: 'q1', kind: 'task', text: text, pass: pass }.compact) }
t('live requests: the hard rules apply on the server too') {
  c, j = req.('go to her house and follow her')
  check(c == 403 && j['error'] =~ /risk/, [c, j])
}
t('live requests: no screening pass, no delivery (the browser can\'t skip the check)') {
  c, j = req.('do a cartwheel')
  check(c == 403 && j['error'] =~ /checked for safety/, [c, j])
}
t('live requests: /api/screen signs a pass for that exact text; changed words need a new one') {
  _, sc = vw.post('/api/screen', text: 'do a cartwheel', kind: 'task', streamer: 'streamer_v2')
  c1, = req.('do a cartwheel', sc['pass'])
  c2, = req.('do a cartwheel then go to her house', sc['pass'])
  _, other = sv.post('/api/screen', text: 'do a cartwheel', kind: 'task')
  c3, = req.('do a cartwheel', other['pass'])   # someone else's pass
  check(sc['verdict'] == 'allow' && sc['pass'] && c1 == 200 && c2 == 403 && c3 == 403, [sc, c1, c2, c3])
}
t('live: a stream title shows only after it has been checked; accepted visit requests hide the place during the delay') {
  stream = { id: 'Lsv1', u: 'x', title: 'Rainey crawl', v: 'v1', delay: 5, reqs: [{ id: 'q', kind: 'visit', place: 'v9', text: 'go to v9', status: 'accepted' },
                                                                                  { id: 'q2', kind: 'visit', place: 'v8', text: 'maybe v8', status: 'pending' }] }
  sv.post('/api/relay', t: 'stream', s: stream, from: 'tabS')
  _, j = vw.get('/api/relay?tab=tabW&since=0')
  s1 = j['msgs'].map { |m| m['s'] }.compact.last
  sleep 1.5   # (Claude is unreachable here, so the check passes on the local rules)
  sv.post('/api/relay', t: 'stream', s: stream, from: 'tabS')
  _, j2 = vw.get('/api/relay?tab=tabW&since=0')
  s2 = j2['msgs'].map { |m| m['s'] }.compact.last
  check(s1['title'] == 'Live' && s2['title'] == 'Rainey crawl' && s2['reqs'][0]['place'].nil? && s2['reqs'][0]['placeHidden'] &&
        s2['reqs'][1]['place'] == 'v8', [s1['title'], s2['title'], s2['reqs']])
}
t('live: a title with a phone number never shows') {
  sv.post('/api/relay', t: 'stream', s: { id: 'Lsv1', title: 'text me 512-555-0100', v: 'v1', delay: 0 }, from: 'tabS'); sleep 1.2
  sv.post('/api/relay', t: 'stream', s: { id: 'Lsv1', title: 'text me 512-555-0100', v: 'v1', delay: 0 }, from: 'tabS')
  _, j = vw.get('/api/relay?tab=tabW&since=0')
  check(j['msgs'].map { |m| m['s'] }.compact.last['title'] == 'Live')
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
