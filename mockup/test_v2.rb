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
  { uid: 'fff000fff000', title: 'Tomorrow Thing', start: (now + 86_400).iso8601, venue: 'Elsewhere', city: 'Austin', lat: 30.3, lng: -97.7, category: 'comedy' },
  { uid: 'aaa111aaa111', title: 'Laugh Night', start: (now + 2 * 86_400).iso8601, venue: 'Elsewhere', city: 'Austin', lat: 30.3, lng: -97.7, category: 'comedy' },
  { uid: 'ccc222ccc222', title: 'Quiet Lecture', start: (now + 2 * 86_400).iso8601, venue: 'Library', city: 'Austin', lat: 30.3, lng: -97.7, category: 'community' }
]
ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: EVENTS.size, events: EVENTS) }
# a fake push service: records what arrives
$pushes = []
ev.mount_proc('/push') { |q, r| $pushes << { auth: q['Authorization'], enc: q['Content-Encoding'], ttl: q['TTL'], body: q.body.b }; r.status = 201 }
ev.mount_proc('/push-gone') { |_q, r| r.status = 410 }
Thread.new { ev.start }

dir = $dir = Dir.mktmpdir('sq-v2-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
log = File.join(dir, 'server.log')
# a stand-in for Claude Code: keeps the prompt it was given and answers with an empty reply
FAKE_CLAUDE = File.join(dir, 'fake_claude')
File.write(FAKE_CLAUDE, "#!/usr/bin/env ruby\nrequire 'json'\npr = $stdin.read\nFile.write(File.join(#{dir.inspect}, 'last_prompt.txt'), pr)\n" \
  "if (l = pr[/^Lines: (\\[.*\\])$/, 1]) then puts JSON.generate(structured_output: { translations: JSON.parse(l).map { |x| 'ES ' + x } }, duration_ms: 1, total_cost_usd: 0); exit end\n" \
  "puts '{\"structured_output\":{\"say\":\"ok\",\"expression\":\"happy\",\"actions\":[]},\"duration_ms\":1,\"total_cost_usd\":0}'\n")
File.chmod(0o755, FAKE_CLAUDE)
# stand-ins for ffmpeg and whisper.cpp: the "conversion" keeps the bytes, the "transcription" says what it was asked
FAKE_FFMPEG, FAKE_WHISPER = File.join(dir, 'fake_ffmpeg'), File.join(dir, 'fake_whisper')
File.write(FAKE_FFMPEG, "#!/usr/bin/env ruby\nsrc = ARGV[ARGV.index('-i') + 1]\nFile.binwrite(ARGV.last, 'x' * 44 + \"\\0\" * 64_000) if File.size(src) > 500\n")
File.write(FAKE_WHISPER, "#!/usr/bin/env ruby\nputs \" [BLANK_AUDIO] find tacos (music) lang=\#{ARGV[ARGV.index('-l') + 1]} ctx=\#{ARGV[ARGV.index('-ac') + 1]}\"\n")
File.write(File.join(dir, 'fake_model.bin'), 'm')
File.chmod(0o755, FAKE_FFMPEG, FAKE_WHISPER)
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PLACES_FILE' => 'test_places.json', 'SQ_OUTDOORS_FILE' => 'test_outdoors.json',
              'SQ_SIGHTS_FILE' => 'test_sights.json', 'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}", 'SQ_ADMIN_TOKEN' => 'adm',
              'SQ_LIVEKIT_URL' => nil, 'SQ_GOOGLE_PLACES_KEY' => nil, 'SQ_GOOGLE_TTS_KEY' => nil, 'SQ_PUSH_TEST_HOST' => "127.0.0.1:#{EV_PORT}",
              'SQ_ENGINE' => 'cli', 'CLAUDE_BIN' => FAKE_CLAUDE, 'SQ_USE_API_KEY' => nil,
              'SQ_FFMPEG_BIN' => FAKE_FFMPEG, 'SQ_WHISPER_BIN' => FAKE_WHISPER, 'SQ_WHISPER_MODEL' => File.join(dir, 'fake_model.bin') },
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
      q.body = body.is_a?(String) ? body : JSON.generate(body) if body
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

require_relative 'webpush'
UA_KEY = WebPush.new_key; UA_AUTH = SecureRandom.random_bytes(16)
t('push: a phone subscribes; only real push services (or the test one) are accepted') {
  sub = { endpoint: "http://127.0.0.1:#{EV_PORT}/push", keys: { p256dh: WebPush.b64u(WebPush.pub_raw(UA_KEY)), auth: WebPush.b64u(UA_AUTH) } }
  c1, j1 = bo.post('/api/push', sub: sub)
  c2, = bo.post('/api/push', sub: sub.merge(endpoint: 'https://169.254.169.254/latest/meta-data'))
  check(c1 == 200 && j1['devices'] == 1 && c2 == 400, [c1, j1, c2])
}
t('a wave notifies the other person; waving back makes friends and tells the first') {
  amy.post('/api/friend', to: 'bo_v2', action: 'request')
  _, n = bo.post('/api/notifs')
  check(n['unread'] == 1 && n['notifs'][0]['t'] == 'freq' && n['notifs'][0]['from'] == 'amy_v2', n)
  bo.post('/api/friend', to: 'amy_v2', action: 'accept')
  _, n2 = amy.post('/api/notifs')
  check(n2['notifs'].any? { |x| x['t'] == 'friend' && x['from'] == 'bo_v2' }, n2)
}
t('push: the wave reached the phone, encrypted for it alone, signed with the server\'s VAPID key') {
  20.times { break unless $pushes.empty?; sleep 0.1 }
  pz = $pushes.first or raise 'nothing pushed'
  body = pz[:body]
  salt, as_pub, ct = body[0, 16], body[21, 65], body[86..-1]
  shared = UA_KEY.dh_compute_key(WebPush.point(as_pub))
  ikm = WebPush.hkdf(UA_AUTH, shared, "WebPush: info\x00".b + WebPush.pub_raw(UA_KEY) + as_pub, 32)
  cek = WebPush.hkdf(salt, ikm, "Content-Encoding: aes128gcm\x00".b, 16); nonce = WebPush.hkdf(salt, ikm, "Content-Encoding: nonce\x00".b, 12)
  plain = WebPush.gcm_by_hand(cek, nonce, ct[0..-17])[0, ct.size - 16]
  tag_ok = WebPush.gcm_by_hand(cek, nonce, plain) == ct
  msg = JSON.parse(plain.chomp("\x02"))
  key = Net::HTTP.get(URI("#{BASE}/config.js"))[/"vapid":"([^"]+)"/, 1]
  check(tag_ok && msg['body'].include?('amy_v2') && msg['url'] == '/?inbox=1' && pz[:enc] == 'aes128gcm' && pz[:auth].include?("k=#{key}") &&
        pz[:auth] =~ /vapid t=[\w-]+\.[\w-]+\.[\w-]+/, [msg, pz[:auth][0, 40], tag_ok])
  msg['body']
}
t('push: an expired subscription (410) is dropped') {
  bo.post('/api/push', sub: { endpoint: "http://127.0.0.1:#{EV_PORT}/push-gone", keys: { p256dh: WebPush.b64u(WebPush.pub_raw(UA_KEY)), auth: WebPush.b64u(UA_AUTH) } })
  amy.post('/api/friend', to: 'bo_v2', action: 'remove'); amy.post('/api/friend', to: 'bo_v2', action: 'request')   # another notification
  sleep 1
  d = JSON.parse(File.read(File.join($dir, 'data', 'app.json')))
  check(d['push']['bo_v2'].map { |x| x['endpoint'] }.none? { |e| e.end_with?('push-gone') } && d['push']['bo_v2'].size == 1, d['push'])
  bo.post('/api/friend', to: 'amy_v2', action: 'accept')
}
t('the VAPID private key stays on the server (not in config.js, not readable by others)') {
  f = File.join($dir, 'data', 'vapid.json')
  priv = JSON.parse(File.read(f))['private']
  check(!Net::HTTP.get(URI("#{BASE}/config.js")).include?(priv) && (File.stat(f).mode & 0o077).zero?, File.stat(f).mode.to_s(8))
}
t('muting a kind of notification stops it; unknown kinds are ignored') {
  _, m = amy.post('/api/notifs', mute: %w[freq nonsense])
  w1, w2 = Who.new('waver_one'), Who.new('waver_two'); w1.signup; w2.signup
  w1.post('/api/friend', to: 'amy_v2', action: 'request')
  amy.post('/api/notifs', mute: [])
  w2.post('/api/friend', to: 'amy_v2', action: 'request')
  _, j = amy.post('/api/notifs')
  froms = j['notifs'].select { |n| n['t'] == 'freq' }.map { |n| n['from'] }
  check(m['mute'] == ['freq'] && !froms.include?('waver_one') && froms.include?('waver_two'), [m['mute'], froms])
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
  check(names.sort == %w[amy_v2 bo_v2] && q2['board'].map { |r| r['h'] } == ['bo_v2'] &&
        %w[history tacos outdoors culture shows explorer nightowl].include?(q['featured']), [names, q2['board'], q['featured']])
  amy.post('/api/quests/board', hidden: false)
}
t("friends out now: nothing unless they chose to share; then just the place, friends only") {
  _, s1 = bo.get('/api/state')
  amy.post('/api/quests/board', share: true)
  _, s2 = bo.get('/api/state')
  stranger = Who.new('stranger_v2'); stranger.signup
  _, s3 = stranger.get('/api/state')
  o = s2['v2']['out'].first
  check(s1['v2']['out'].empty? && o && o['h'] == 'amy_v2' && o['name'] && !o.key?('lat') && s3['v2']['out'].empty?, [s1['v2']['out'], s2['v2']['out']])
  o['name']
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
t('group chat: members only; posting notifies members who have talked there') {
  _, g = bo.post('/api/group/create', n: 'Test Pickup Soccer', d: 'Sundays at Zilker', e: '⚽', cat: 'sports')
  gid = (g['group'] || g)['id'] || g.dig('group', 'id')
  c0, = amy.post('/api/group/chat', id: gid)
  bo.post('/api/group/chat', id: gid, text: 'Field 3 this Sunday?')
  amy.post('/api/group/join', id: gid, on: true)
  _, j = amy.post('/api/group/chat', id: gid, text: 'In! Bringing a ball')
  _, n = bo.post('/api/notifs')
  check(c0 == 403 && j['msgs'].map { |m| m['t'] } == ['Field 3 this Sunday?', 'In! Bringing a ball'] &&
        n['notifs'].any? { |x| x['t'] == 'chat' && x['ref'] == "g:#{gid}" } && n['notifs'].any? { |x| x['t'] == 'join' }, [c0, j, gid])
}
# ---- Messenger-style chats (chats.rb)
ca, cb, cc, cz = Who.new('chat_a'), Who.new('chat_b'), Who.new('chat_c'), Who.new('chat_z')
[ca, cb, cc, cz].each(&:signup)
[[ca, cb], [ca, cc], [cb, cc]].each { |x, y| x.post('/api/friend', to: y.h, action: 'request'); y.post('/api/friend', to: x.h, action: 'accept') }
$m1 = nil
t('chat: send, reply quoting a message, react, unread count and seen') {
  _, j = ca.post('/api/dm/send', to: 'chat_b', text: 'Pool tonight?')
  $m1 = j['msg']['id']
  _, th = cb.get('/api/dm/threads')
  t1 = th['threads'].find { |x| x['with'] == 'chat_a' }
  _, r = cb.post('/api/dm/send', to: 'chat_a', text: 'yes! 9?', re: $m1)
  _, rx = cb.post('/api/dm/react', to: 'chat_a', id: $m1, e: '🔥')
  cb.post('/api/dm/read', to: 'chat_a')
  _, dm = ca.get('/api/dm?with=chat_b')
  _, n = ca.post('/api/notifs')
  check(t1 && t1['unread'] == 1 && r['msg']['re']['t'] == 'Pool tonight?' && rx['rx'] == { 'chat_b' => '🔥' } &&
        dm['seen']['chat_b'] >= r['msg']['at'] && n['notifs'].any? { |x| x['t'] == 'dm' && x['ref'] == 'chat_b' } &&
        dm['msgs'].find { |m| m['id'] == $m1 }['rx'] == { 'chat_b' => '🔥' }, [t1, r, rx, dm['seen']])
}
t('chat: tapping the same reaction again takes it off; only the six reactions') {
  _, rx = cb.post('/api/dm/react', to: 'chat_a', id: $m1, e: '🔥')
  c, = cb.post('/api/dm/react', to: 'chat_a', id: $m1, e: '💩')
  check(rx['rx'] == {} && c == 400, [rx, c])
}
t('chat: typing shows to the other person for a few seconds') {
  ca.post('/api/dm/typing', to: 'chat_b')
  _, dm = cb.get('/api/dm?with=chat_a'); _, own = ca.get('/api/dm?with=chat_b')
  check(dm['typing'] == ['chat_a'] && own['typing'] == [], [dm['typing'], own['typing']])
}
t('chat: photo and a shared event card; photo only for signed-in people') {
  jpg = 'data:image/jpeg;base64,' + ['\xFF\xD8\xFF\xE0'.b + 'x' * 300].pack('m0')
  _, j = ca.post('/api/dm/send', to: 'chat_b', img: jpg, text: 'look')
  _, k = ca.post('/api/dm/send', to: 'chat_b', card: { k: 'event', id: 'e:abc123def456', name: 'Test Show', sub: 'Tonight', e: '🎸', junk: 'x' })
  c1 = cb.req(:get, j['msg']['img']).first
  c2 = Net::HTTP.get_response(URI("#{BASE}#{j['msg']['img']}")).code.to_i
  bad, = ca.post('/api/dm/send', to: 'chat_b', img: 'data:image/png;base64,AAAA')
  check(j['msg']['img'] =~ %r{\A/dm-img/i[0-9a-f]{16}\.jpg\z} && c1 == 200 && c2 == 404 && bad == 400 &&
        k['msg']['card'] == { 'k' => 'event', 'id' => 'e:abc123def456', 'name' => 'Test Show', 'sub' => 'Tonight', 'e' => '🎸' }, [j, k, c1, c2, bad])
  $img = j['msg']
}
t('chat: voice note upload, then send; plays in ranges; someone else cannot reuse its id') {
  c, up = ca.req(:post, '/api/dm/voice', 'a' * 5000, 'Content-Type' => 'audio/mp4')
  stolen, = cc.post('/api/dm/send', to: 'chat_a', aud: up['id'])
  _, j = ca.post('/api/dm/send', to: 'chat_b', aud: up['id'], dur: 7)
  again, = ca.post('/api/dm/send', to: 'chat_b', aud: up['id'])
  rc, = cb.req(:get, j['msg']['aud'], nil, 'Range' => 'bytes=0-99')
  wrong, = ca.req(:post, '/api/dm/voice', 'a' * 5000, 'Content-Type' => 'text/plain')
  check(c == 200 && stolen == 400 && j['msg']['aud'] == "/dm-aud/#{up['id']}" && j['msg']['dur'] == 7 && again == 400 && rc == 206 && wrong == 400,
        [c, up, stolen, j, again, rc, wrong])
}
t('chat: unsend your own (photo deleted), not someone else\'s') {
  no, = cb.post('/api/dm/unsend', to: 'chat_a', id: $img['id'])
  ca.post('/api/dm/unsend', to: 'chat_b', id: $img['id'])
  _, dm = cb.get('/api/dm?with=chat_a')
  m = dm['msgs'].find { |x| x['id'] == $img['id'] }
  check(no == 403 && m['gone'] && !m.key?('img') && !m.key?('t') && cb.req(:get, $img['img']).first == 404, [no, m])
}
t('chat: strangers can\'t message; group chats need 2+ friends') {
  c1, = cz.post('/api/dm/send', to: 'chat_a', text: 'hey')
  c2, = ca.post('/api/chat/new', members: ['chat_b'])
  c3, = ca.post('/api/chat/new', members: %w[chat_b chat_z])
  check(c1 == 403 && c2 == 400 && c3 == 400, [c1, c2, c3])
}
t('group chat: create, everyone notified, messages, seen by, rename, add, leave; outsiders kept out') {
  _, g = ca.post('/api/chat/new', name: 'Saturday crew', members: %w[chat_b chat_c chat_z])
  w = g['with']
  _, nb = cb.post('/api/notifs')
  _, th0 = cc.get('/api/dm/threads')
  cb.post('/api/dm/send', to: w, text: 'Zilker at 2?')
  _, th = cc.get('/api/dm/threads')
  cc.post('/api/dm/read', to: w)
  _, dm = cb.get("/api/dm?with=#{URI.encode_www_form_component(w)}")
  out, = cz.get("/api/dm?with=#{URI.encode_www_form_component(w)}")
  out2, = cz.post('/api/dm/send', to: w, text: 'let me in')
  _, r = cb.post('/api/chat/edit', id: w, name: 'Sat crew 🌳')
  ca.post('/api/chat/edit', id: w, leave: true)
  _, after = cb.get("/api/dm?with=#{URI.encode_www_form_component(w)}")
  gone, = ca.get("/api/dm?with=#{URI.encode_www_form_component(w)}")
  tt = th['threads'].find { |x| x['with'] == w }
  check(w =~ /\Ac:[0-9a-f]{10}\z/ && nb['notifs'].any? { |x| x['t'] == 'dm' && x['ref'] == w } && th0['threads'].any? { |x| x['with'] == w } &&
        tt && tt['name'] == 'Saturday crew' && tt['unread'] == 1 && dm['seen']['chat_c'] > 0 && dm['chat']['members'] == %w[chat_a chat_b chat_c] &&
        out == 403 && out2 == 403 && r['chat']['name'] == 'Sat crew 🌳' && after['chat']['members'] == %w[chat_b chat_c] &&
        after['msgs'].last['sys'] && gone == 403, [g, tt, dm, r, after['chat'], gone])
}
t('chat: blocking hides the chat and stops messages') {
  cc.post('/api/block', who: 'chat_b', on: true)
  c, = cb.post('/api/dm/send', to: 'chat_c', text: 'hi?')
  _, th = cc.get('/api/dm/threads')
  check(c == 403 && th['threads'].none? { |x| x['with'] == 'chat_b' }, [c, th])
}
t("a link made up in someone else's name can't make you their friend") {
  mal = Who.new('mallory_v2'); mal.signup(ref: 'amy_v2', ref_friend: true, rk: '000000000000')
  _, s = mal.get('/api/state')
  check(!s['friends']['list'].include?('amy_v2'), s['friends'])
}
t('invite link: the new person can choose to be friends with whoever invited them') {
  _, as = amy.get('/api/state')
  page = Net::HTTP.get(URI("#{BASE}/i/amy_v2/#{as['v2']['invite']}"))
  check(page.include?("rk=#{as['v2']['invite']}"), 'invite page lost the code')
  cy.signup(ref: 'amy_v2', ref_friend: true, rk: as['v2']['invite'])
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
  check(c1 == 403 && c2 == 200 && g['events']['event_open'] == 2 && !g['events'].key?('evil_thing') && g['dau'].last >= 2 && g['users'] == 11, g)   # 7 + the 4 chat testers
  "dau #{g['dau'].last}, wau #{g['wau']}"
}
t("friends see each other's level and badges; a stranger's quests stay private") {
  _, sb = bo.get('/api/state'); _, sc = Who.new('nobody').tap(&:signup).get('/api/state')
  check(sb['badges']['amy_v2'] && sb['badges']['amy_v2']['done'].include?('history') && !sc['badges'].key?('amy_v2'), [sb['badges'], sc['badges']])
}
t("Scout knows what you've enjoyed and suggests more like it") {
  amy.post('/api/rsvp', id: 'e:fff000fff000', status: 'going')   # a comedy show at Elsewhere
  c, = amy.post('/api/scout', q: 'what should I do this weekend?', context: { events: [] })
  pr = File.read(File.join($dir, 'last_prompt.txt'))
  taste = pr[/What this user has enjoyed before.*?: (\{.*?\})\. When you recommend/, 1]
  check(c == 200 && taste && JSON.parse(taste)['event_types'].include?(['comedy', 3.0]) && taste.include?('Went to Tomorrow Thing at Elsewhere'), taste || pr[0, 300])
  ev = pr[/"events":(\[.*?\])[,}]/, 1].to_s
  check(ev.include?('e:aaa111aaa111') && ev.include?("you've been to Elsewhere and you like comedy") && !ev.include?('Quiet Lecture'), ev[0, 300])
  "fits: Laugh Night"
}
t('taking back an RSVP takes it out of what Scout thinks you like') {
  amy.post('/api/rsvp', id: 'e:fff000fff000', status: nil)
  amy.post('/api/scout', q: 'what should I do this weekend?', context: { events: [] })
  pr = File.read(File.join($dir, 'last_prompt.txt'))
  check(!pr.include?('Went to Tomorrow Thing'), pr[/What this user has enjoyed.{0,200}/])
}
t('deleting an account removes its notifications, quests and saves') {
  amy.post('/api/account/delete', pw: 'password123', confirm: true)
  sleep 0.3
  d = JSON.parse(File.read(File.join($dir, 'data', 'app.json')))
  check(!(d['quest'] || {}).key?('amy_v2') && !(d['saves'] || {}).key?('amy_v2') && !(d['notifs'] || {}).key?('amy_v2') && !(d['taste'] || {}).key?('amy_v2') &&
        (d['notifs'] || {}).values.flatten.none? { |n| n['from'] == 'amy_v2' }, d.slice('quest', 'saves').keys)
}

t('Scout\'s ears: a recording becomes text on the server (signed in only), cleaned of [BLANK_AUDIO]-style marks') {
  audio = 'a' * 4000
  guest = Who.new('nobody'); ears = Who.new('ears_v2'); ears.signup
  cg, = guest.req(:post, '/api/scout/hear?lang=en', audio, 'Content-Type' => 'audio/mp4')
  c1, j1 = ears.req(:post, '/api/scout/hear?lang=es', audio, 'Content-Type' => 'audio/mp4')
  c2, j2 = ears.req(:post, '/api/scout/hear?lang=xx&partial=1', audio, 'Content-Type' => 'audio/webm')
  c3, = ears.req(:post, '/api/scout/hear', 'a' * 50, 'Content-Type' => 'audio/mp4')
  c4, j4 = ears.req(:post, '/api/scout/hear', 'a' * 300, 'Content-Type' => 'audio/mp4')   # unreadable: ffmpeg makes nothing
  cfg = Net::HTTP.get(URI("#{BASE}/config.js"))
  check(cg == 401 && c1 == 200 && j1['text'] == 'find tacos lang=es ctx=256' && c2 == 200 && j2['text'] == 'find tacos lang=en ctx=256' &&
        c3 == 400 && c4 == 400 && j4['error'] =~ /couldn't read/ && cfg.include?('"hear":true'), [cg, c1, j1, c2, j2, c3, c4, j4, cfg[0, 80]])
}

t('Live Translate: camera text is translated (signed in only), line breaks kept, repeats come from the cache') {
  tr = Who.new('lens_v2'); tr.signup
  cg, = Who.new('nobody2').post('/api/translate', lines: ['Hello'], to: 'es')
  c1, j1 = tr.post('/api/translate', lines: ["TACOS  AL PASTOR\n  $3.50", '', 'Open late'], from: 'en', to: 'es')
  File.delete(File.join($dir, 'last_prompt.txt'))
  c2, j2 = tr.post('/api/translate', lines: ['Open late'], from: 'en', to: 'es')
  cached = !File.exist?(File.join($dir, 'last_prompt.txt'))
  c3, = tr.post('/api/translate', lines: ['x'], to: 'klingon')
  c4, = tr.post('/api/translate', lines: ['  '], to: 'fr')
  check(cg == 401 && c1 == 200 && j1['translations'] == ["ES TACOS AL PASTOR\n$3.50", '', 'ES Open late'] && c2 == 200 &&
        j2['translations'] == ['ES Open late'] && cached && c3 == 400 && c4 == 400, [cg, c1, j1, c2, j2, cached, c3, c4])
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
