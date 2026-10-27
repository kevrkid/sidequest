# Live video safety rules in server.rb, against a fake LiveKit API (no LiveKit, no internet): ruby test_live.rb
# Runs a throwaway copy of the server on :8795 with its own empty data folder, so your real data is untouched.
require 'webrick'; require 'json'; require 'net/http'; require 'openssl'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8795; LK_PORT = 9912; KEY = 'testkey'; SECRET = 's' * 40; ADMIN = 'admintest'
BASE = URI("http://127.0.0.1:#{PORT}")

$lk = []   # [method, body, jwt claims] for every LiveKit API call
$ingress = {}; $n = 0   # fake LiveKit Ingress: camera addresses by id
$lk_down = false        # true: ListIngress answers 500, like a LiveKit hiccup
lk = WEBrick::HTTPServer.new(Port: LK_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
lk.mount_proc('/twirp') do |req, res|
  head, body, sig = req['Authorization'].to_s.sub('Bearer ', '').split('.')
  ok = sig == [OpenSSL::HMAC.digest('SHA256', SECRET, "#{head}.#{body}")].pack('m0').tr('+/', '-_').delete('=')
  claims = ok ? JSON.parse(body.tr('-_', '+/').then { |s| s + '=' * (-s.size % 4) }.unpack1('m')) : nil
  m, b = req.path.split('/').last, JSON.parse(req.body)
  $lk << [m, b, claims]
  res['Content-Type'] = 'application/json'
  res.status = !ok ? 401 : $lk_down && m == 'ListIngress' ? 500 : 200
  res.body = JSON.generate(
    case m
    when 'CreateIngress'
      id = "IN_#{$n += 1}"
      $ingress[id] = { ingress_id: id, url: 'rtmps://fake.rtmp.livekit.cloud/x', stream_key: "sk_#{$n}", room_name: b['room_name'], state: {} }
    when 'ListIngress' then { items: [$ingress[b['ingress_id']]].compact }
    when 'DeleteIngress' then $ingress.delete(b['ingress_id']) || {}
    when 'StartRoomCompositeEgress' then { egress_id: 'EG_1', status: 'EGRESS_STARTING' }
    when 'ListEgress' then { items: [{ egress_id: b['egress_id'], status: 'EGRESS_ACTIVE' }] }
    else {}
    end)
end
Thread.new { lk.start }

dir = $dir = Dir.mktmpdir('sq-live-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json}')], dir)
log = File.join(dir, 'server.log')
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_LIVEKIT_URL' => "ws://127.0.0.1:#{LK_PORT}", 'SQ_LIVEKIT_KEY' => KEY,
              'SQ_LIVEKIT_SECRET' => SECRET, 'SQ_ADMIN_TOKEN' => ADMIN, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0',
              'SQ_PLACES_FILE' => 'test_places.json', 'SQ_LIVEKIT_API_URL' => nil },
            'ruby', 'server.rb', chdir: dir, out: log, err: log)
at_exit { Process.kill('TERM', pid) rescue nil; FileUtils.rm_rf(dir) }

def call(path, body = nil, cookie = nil, admin = false)
  Net::HTTP.start(BASE.host, BASE.port) do |http|
    req = body ? Net::HTTP::Post.new(path, 'Content-Type' => 'application/json') : Net::HTTP::Get.new(path)
    req['Cookie'] = "sq_s=#{cookie}" if cookie
    req['X-Admin-Token'] = ADMIN if admin
    req.body = JSON.generate(body) if body
    r = http.request(req)
    [r.code.to_i, (JSON.parse(r.body) rescue {}), r['Set-Cookie'].to_s[/sq_s=([^;]+)/, 1]]
  end
end

def jwt(tok)
  JSON.parse(tok.split('.')[1].tr('-_', '+/').then { |s| s + '=' * (-s.size % 4) }.unpack1('m'))
end

def signup(h)
  code, j, cookie = call('/api/signup', { h: h, pw: 'correct horse 9', adult: true, terms: true })
  raise "signup #{h}: #{code} #{j}" unless code == 200 && cookie
  cookie
end

def poll(cookie, since)
  _, j, = call("/api/relay?tab=t#{cookie[0, 4]}&since=#{since}", nil, cookie)
  j
end

$pass = $fail = 0
def t(name)
  r = yield
  $pass += 1; puts "PASS #{name}#{r.is_a?(String) ? "  [#{r}]" : ''}"
rescue => e
  $fail += 1; puts "FAIL #{name}: #{e.message}"
end
def check(c, m) raise m unless c end

40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
amy, bo, cy = signup('test_amy'), signup('test_bo'), signup('test_cy')
stream = { id: 'Ltabamy', u: 'somebody_else', title: 'Sunset swim', v: 'bw', delay: 5, room: 'live-somebody_else', reqs: [], viewers: 0 }

t('streamer gets a publish pass for their own room only') {
  code, j, = call('/api/live/token', { publish: true }, amy)
  c = jwt(j['token'])
  check(code == 200 && j['room'] == 'live-test_amy' && c['sub'] == 'test_amy', "#{code} #{j}")
  # canSubscribe: the streamer sees their own action camera's picture and counts viewers
  check(c['video'] == { 'room' => 'live-test_amy', 'roomJoin' => true, 'canPublish' => true, 'canSubscribe' => true, 'canPublishData' => false }, c.inspect)
  "exp in #{c['exp'] - Time.now.to_i}s"
}
t('no watch pass for someone who is not live (their camera key may be streaming into the room)') {
  code, = call('/api/live/token', { room: 'live-test_amy' }, bo)
  check(code == 403, code.to_s)
}
since = poll(bo, -1)['seq']
t('announcements go out under the real account and room, spot held back by the delay') {
  code, = call('/api/relay', { t: 'stream', s: stream, from: 'tabamy', mid: 'm1' }, amy)
  m = poll(bo, since)['msgs'].find { |x| x['t'] == 'stream' } or raise 'no announcement'
  s = m['s']
  check(code == 200 && s['u'] == 'test_amy' && s['room'] == 'live-test_amy' && m['by'] == 'test_amy', s.inspect)
  check(s['v'].nil? && s['startedAt'].is_a?(Integer), "venue leaked during the 5-min delay: #{s['v'].inspect}")
  'venue hidden'
}
t('viewers get an anonymous watch-only pass once the stream is on') {
  _, j, = call('/api/live/token', { room: 'live-test_amy' }, bo)
  c = jwt(j['token'])
  check(c['sub'] =~ /\Av[0-9a-f]{12}\z/ && c['name'] == '' && !c['video']['canPublish'] && c['video']['canSubscribe'], c.inspect)
  c['sub']
}
t('no delay chosen: the venue shows') {
  since = poll(bo, -1)['seq']
  call('/api/relay', { t: 'stream', s: stream.merge(delay: 0), from: 'tabamy', mid: 'm2' }, amy)
  s = poll(bo, since)['msgs'].find { |x| x['t'] == 'stream' }['s']
  check(s['v'] == 'bw', s['v'].inspect)
}
t("nobody can end or take over someone else's stream") {
  c1, = call('/api/relay', { t: 'end', id: 'Ltabamy', from: 'tabbo', mid: 'm3' }, bo)
  c2, = call('/api/relay', { t: 'stream', s: stream.merge(title: 'hijack'), from: 'tabbo', mid: 'm4' }, bo)
  check(c1 == 403 && c2 == 403, "#{c1} #{c2}")
}
t('Report while watching names the streamer for the admin') {
  code, = call('/api/report', { kind: 'stream', id: 'Ltabamy', reason: 'Harassment' }, bo)
  _, a, = call('/api/admin', nil, nil, true)
  r = a['reports'].first
  check(code == 200 && r['kind'] == 'stream' && r['about'] == 'test_amy' && r['by'] == 'test_bo', r.inspect)
  check(a['live'].map { |s| s['h'] } == ['test_amy'] && a['livekit'] == true, a['live'].inspect)
}
t('blocks hide streams and refuse watch passes, both ways') {
  call('/api/block', { who: 'test_amy' }, cy)
  since = poll(cy, -1)['seq']
  call('/api/relay', { t: 'stream', s: stream, from: 'tabamy', mid: 'm5' }, amy)
  hidden = poll(cy, since)['msgs'].none? { |x| x['by'] == 'test_amy' }
  code, = call('/api/live/token', { room: 'live-test_amy' }, cy)
  call('/api/block', { who: 'test_amy', on: false }, cy)
  check(hidden && code == 403, "hidden=#{hidden} token=#{code}")
}
t('camera address (RTMP ingest): made once, kept, its own room, key only for its owner') {
  $lk.clear
  _, a1, = call('/api/live/ingress', { action: 'get' }, amy)
  _, a2, = call('/api/live/ingress', { action: 'get' }, amy)
  _, b1, = call('/api/live/ingress', { action: 'get' }, bo)
  made = $lk.select { |m, _, _| m == 'CreateIngress' }
  check(a1['key'] == a2['key'] && a1['url'] =~ %r{\Artmps://} && b1['key'] != a1['key'], "#{a1} #{a2} #{b1}")
  check(made.map { |_, b, _| [b['room_name'], b['participant_identity']] } == [%w[live-test_amy test_amy~cam], %w[live-test_bo test_bo~cam]], made.inspect)
  check(made.all? { |_, _, c| c && c['video'] == { 'ingressAdmin' => true } }, 'ingress calls not signed as ingressAdmin')
  check(a1['status'] == 'ENDPOINT_INACTIVE', a1['status'].inspect)
}
t('New key: the old camera key is deleted') {
  _, before, = call('/api/live/ingress', { action: 'status' }, amy); $lk.clear
  _, after, = call('/api/live/ingress', { action: 'reset' }, amy)
  check(after['key'] != before['key'] && $lk.any? { |m, _, _| m == 'DeleteIngress' } && $ingress.size == 2, "#{before} #{after} #{$lk.map(&:first)}")
}
t('a LiveKit hiccup never swaps the camera key behind your back') {
  _, before, = call('/api/live/ingress', { action: 'status' }, amy)
  $lk_down = true; $lk.clear
  c1, j1, = call('/api/live/ingress', { action: 'get' }, amy)
  c2, = call('/api/live/ingress', { action: 'status' }, amy)
  $lk_down = false
  _, after, = call('/api/live/ingress', { action: 'get' }, amy)
  check(c1 == 400 && j1['error'] =~ /LiveKit/ && c2 == 400 && $lk.none? { |m, _, _| m == 'CreateIngress' }, "#{c1} #{j1} #{c2} #{$lk.map(&:first)}")
  check(after['key'] == before['key'], "#{before} #{after}")
}
t('checking the camera every 3 s for an hour is fine; making keys is rate-limited') {
  eve = signup('test_eve')
  codes = Array.new(300) { call('/api/live/ingress', { action: 'status' }, eve)[0] }
  gets = Array.new(31) { call('/api/live/ingress', { action: 'get' }, eve)[0] }
  check(codes.uniq == [200] && gets[0, 30].uniq == [200] && gets[30] == 429, "status #{codes.uniq} get #{gets}")
  '300 checks ok, 31st key request refused'
}
t('copy-out needs you live, and a real rtmp:// address') {
  c1, j1, = call('/api/live/restream', { action: 'start', targets: [{ url: 'rtmps://a.rtmps.youtube.com/live2', key: 'abcd-1234' }] }, bo)
  c2, j2, = call('/api/live/restream', { action: 'start', targets: [{ url: 'http://evil.example/x', key: 'abcd-1234' }] }, amy)
  check(c1 == 400 && j1['error'] =~ /Go live first/ && c2 == 400 && j2['error'] =~ /rtmp/, "#{c1} #{j1} #{c2} #{j2}")
}
t('copy-out sends your own room to YouTube/TikTok, keys never stored') {
  call('/api/relay', { t: 'stream', s: stream, from: 'tabamy', mid: 'm5b' }, amy); $lk.clear
  code, j, = call('/api/live/restream', { action: 'start', targets: [{ url: 'rtmps://a.rtmps.youtube.com/live2', key: 'abcd-1234' },
                                                                     { url: 'rtmp://push.tiktokcdn.com/game/', key: 'stream-77?expire=1' }] }, amy)
  eg = $lk.find { |m, _, _| m == 'StartRoomCompositeEgress' } or raise "no egress: #{j}"
  check(code == 200 && eg[1]['room_name'] == 'live-test_amy' && eg[1]['stream_outputs'] == [{ 'protocol' => 'RTMP',
        'urls' => ['rtmps://a.rtmps.youtube.com/live2/abcd-1234', 'rtmp://push.tiktokcdn.com/game/stream-77?expire=1'] }], eg.inspect)
  _, st, = call('/api/live/restream', { action: 'status' }, amy)
  sleep 0.3
  saved = Dir[File.join($dir, 'data', '*.json')].map { |f| File.read(f) }.join
  check(st['status'] == 'EGRESS_ACTIVE' && !saved.include?('abcd-1234') && !saved.include?('stream-77'), "#{st} stored=#{saved.include?('abcd-1234')}")
}
t('admin End stream: LiveKit room deleted, viewers told, streamer locked out') {
  since = poll(bo, -1)['seq']; $lk.clear
  code, j, = call('/api/admin', { action: 'end_stream', h: 'test_amy' }, nil, true)
  sleep 0.5
  del = $lk.find { |m, b, _| m == 'DeleteRoom' && b == { 'room' => 'live-test_amy' } } or raise "no DeleteRoom: #{$lk.inspect}"
  check(code == 200 && del[2] && del[2]['iss'] == KEY && del[2]['video'] == { 'roomCreate' => true }, "#{j} #{del.inspect}")
  ended = poll(bo, since)['msgs'].find { |x| x['t'] == 'end' }
  check(ended && ended['id'] == 'Ltabamy' && ended['killed'] == true && ended['by'].nil?, ended.inspect)
  r1, = call('/api/relay', { t: 'stream', s: stream, from: 'tabamy', mid: 'm6' }, amy)
  r2, = call('/api/live/token', { publish: true }, amy)
  r3, j3, = call('/api/live/token', { room: 'live-test_amy' }, bo)
  check(r1 == 410 && r2 == 403 && r3 == 403, "relay #{r1}, publish #{r2}, watch #{r3} #{j3}")
  _, a, = call('/api/admin', nil, nil, true)
  check(a['live'].empty? && a['live_stopped'].map { |x| x['h'] } == ['test_amy'], a['live'].inspect)
  check($lk.any? { |m, b, _| m == 'StopEgress' && b['egress_id'] == 'EG_1' }, "copy-out not stopped: #{$lk.map(&:first)}")
  check($lk.any? { |m, _, _| m == 'DeleteIngress' } && $ingress.values.none? { |x| x[:room_name] == 'live-test_amy' }, 'camera key still works')
  ri, = call('/api/live/ingress', { action: 'get' }, amy)
  check(ri == 403, "locked-out streamer got a new camera key: #{ri}")
  'DeleteRoom signed with the LiveKit key; copy-out stopped; camera key revoked'
}
t('viewers cannot fake a moderator stop') {
  since = poll(cy, -1)['seq']
  call('/api/relay', { t: 'end', id: 'Lsomething', killed: true, from: 'tabbo', mid: 'm7' }, bo)
  m = poll(cy, since)['msgs'].find { |x| x['t'] == 'end' }
  check(m && !m.key?('killed'), m.inspect)
}
t('suspending someone also ends their LiveKit room') {
  $lk.clear
  call('/api/admin', { action: 'ban', h: 'test_cy' }, nil, true)
  sleep 0.5
  check($lk.any? { |m, b, _| m == 'DeleteRoom' && b['room'] == 'live-test_cy' }, $lk.inspect)
}
dee = signup('test_dee')
cam = { id: 'Ltabdee', u: 'test_dee', title: 'GoPro ride', v: 'bw', delay: 0, room: 'live-test_dee', reqs: [], viewers: 0, ingest: true }
t("camera stream: Go live before the camera's picture arrives is held, not shown") {
  _, ig, = call('/api/live/ingress', { action: 'get' }, dee)
  $dee_ing = $ingress.find { |_, x| x[:stream_key] == ig['key'] }[0]
  since = poll(bo, -1)['seq']
  code, j, = call('/api/relay', { t: 'stream', s: cam, from: 'tabdee', mid: 'c1' }, dee)
  sleep 3.5
  shown = poll(bo, since)['msgs'].any? { |x| x['by'] == 'test_dee' }
  w, = call('/api/live/token', { room: 'live-test_dee' }, bo)
  _, a, = call('/api/admin', nil, nil, true)
  check(code == 200 && j['held'] && !shown && w == 403 && a['live'].none? { |s| s['h'] == 'test_dee' }, "#{code} #{j} shown=#{shown} watch=#{w}")
}
t("camera stream: on the air when the picture arrives, and kept there while the phone app is in the background") {
  since = poll(bo, -1)['seq']
  $ingress[$dee_ing][:state] = { status: 'ENDPOINT_PUBLISHING' }
  sleep 4
  first = poll(bo, since)['msgs'].select { |x| x['t'] == 'stream' && x['by'] == 'test_dee' }
  since2 = poll(bo, -1)['seq']
  sleep 7   # the phone app sends nothing now
  later = poll(bo, since2)['msgs'].select { |x| x['t'] == 'stream' && x['by'] == 'test_dee' }
  w, = call('/api/live/token', { room: 'live-test_dee' }, bo)
  s = first.first && first.first['s']
  check(s && s['room'] == 'live-test_dee' && s['u'] == 'test_dee' && first.first['from'] == 'tabdee' && s['startedAt'], first.inspect)
  check(later.any? && w == 200, "re-announced #{later.size}x, watch #{w}")
  "#{later.size} server re-announcements in 7 s"
}
t('camera stream: viewers are told when the camera stops; blocked viewers never see it') {
  gil = signup('test_gil')
  call('/api/block', { who: 'test_dee' }, gil)
  sc = poll(gil, -1)['seq']
  since = poll(bo, -1)['seq']
  $ingress[$dee_ing][:state] = { status: 'ENDPOINT_INACTIVE' }
  sleep 19
  ended = poll(bo, since)['msgs'].find { |x| x['t'] == 'end' && x['id'] == 'Ltabdee' }
  leaked = poll(gil, sc)['msgs'].any? { |x| x['by'] == 'test_dee' }
  _, a, = call('/api/admin', nil, nil, true)
  check(ended && !leaked && a['live'].none? { |s| s['h'] == 'test_dee' }, "ended=#{ended.inspect} leaked=#{leaked}")
}
t('camera stream: a moderator stop takes it off the air for good') {
  $ingress[$dee_ing][:state] = { status: 'ENDPOINT_PUBLISHING' }
  call('/api/relay', { t: 'stream', s: cam, from: 'tabdee', mid: 'c2' }, dee)
  sleep 4
  _, a1, = call('/api/admin', nil, nil, true)
  call('/api/admin', { action: 'end_stream', h: 'test_dee' }, nil, true)
  since = poll(bo, -1)['seq']
  sleep 4
  back = poll(bo, since)['msgs'].any? { |x| x['t'] == 'stream' && x['by'] == 'test_dee' }
  check(a1['live'].any? { |s| s['h'] == 'test_dee' } && !back && !$ingress.key?($dee_ing), "was live=#{a1['live'].map { |s| s['h'] }} back=#{back}")
}
t('deleting an account deletes its camera key') {
  call('/api/live/ingress', { action: 'get' }, eve = signup('test_fay'))
  id = $ingress.find { |_, x| x[:room_name] == 'live-test_fay' }[0]
  code, = call('/api/account/delete', { pw: 'correct horse 9' }, eve)
  sleep 0.5
  check(code == 200 && !$ingress.key?(id), "#{code} still there=#{$ingress.key?(id)}")
}
puts "#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
