# Find friends by email / phone (contacts.rb) against a throwaway copy of the server (no internet, no real Claude):
# ruby test_contacts.rb
# Only people who opted in are found, only by the exact email / number, nothing raw is stored or sent to others,
# blocks hide both ways, unlinking and deleting the account remove it, and the match endpoint is rate-limited.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8807; EV_PORT = 9919
BASE = "http://127.0.0.1:#{PORT}"

ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: 0, events: []) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-contacts-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
FileUtils.mkdir_p(File.join(dir, 'data')); File.write(File.join(dir, 'data', 'app.json'), '{}')
log = File.join(dir, 'server.log')
DOWN = File.join(dir, 'claude_down')            # exists = Claude can't be reached
CHECKED = File.join(dir, 'checked.txt')         # one line per text Claude was shown: its length
# a stand-in for Claude Code: text checks block anything with BADWORD; everything else gets an empty reply
FAKE = File.join(dir, 'fake_claude')
File.write(FAKE, "#!/usr/bin/env ruby\nrequire 'json'\npr = $stdin.read\nexit 1 if File.exist?(#{DOWN.inspect})\n" \
  "if (t = pr[/Text to check:\\n(\".*\")\\nGive a verdict/m, 1]) then t = JSON.parse(t)\n" \
  "  File.open(#{CHECKED.inspect}, 'a') { |f| f.puts t.size }; sleep 3 if t.include?('SLOWWORD')\n" \
  "  bad = t.include?('BADWORD'); puts JSON.generate(type: 'result', structured_output: { verdict: bad ? 'block' : 'allow', reason: bad ? 'That word is not allowed here.' : 'ok' }, duration_ms: 1, total_cost_usd: 0); exit end\n" \
  "puts '{\"structured_output\":{\"say\":\"ok\",\"expression\":\"happy\",\"actions\":[]},\"duration_ms\":1,\"total_cost_usd\":0}'\n")
File.chmod(0o755, FAKE)
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PHOTO_SCREEN' => '0', 'SQ_PLACES_FILE' => 'test_places.json',
              'SQ_OUTDOORS_FILE' => 'test_outdoors.json', 'SQ_SIGHTS_FILE' => 'test_sights.json', 'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}",
              'SQ_ADMIN_TOKEN' => 'adm', 'SQ_LIVEKIT_URL' => nil, 'SQ_GOOGLE_PLACES_KEY' => nil, 'SQ_GOOGLE_TTS_KEY' => nil,
              'SQ_ENGINE' => 'cli', 'CLAUDE_BIN' => FAKE, 'SQ_USE_API_KEY' => nil, 'SQ_PROFILE_RECHECK_S' => '1' },
            'ruby', 'server.rb', chdir: dir, out: log, err: log)
at_exit do
  begin Process.kill('TERM', pid); 30.times { break if Process.waitpid(pid, Process::WNOHANG); sleep 0.1 }; Process.kill('KILL', pid) rescue nil
  rescue StandardError then nil
  end
  FileUtils.rm_rf(dir)
end

class Who
  attr_reader :h
  def initialize(h) @h = h; @c = nil end
  def req(m, path, body = nil)
    u = URI("#{BASE}#{path}")
    r = Net::HTTP.start(u.host, u.port) do |http|
      q = m == :get ? Net::HTTP::Get.new(u) : Net::HTTP::Post.new(u, 'Content-Type' => 'application/json')
      q['Cookie'] = "sq_s=#{@c}" if @c
      q.body = JSON.generate(body) if body
      http.request(q)
    end
    @c = r['Set-Cookie'][/sq_s=([^;]+)/, 1] if r['Set-Cookie'].to_s.include?('sq_s=')
    [r.code.to_i, (JSON.parse(r.body) rescue r.body)]
  end
  def post(p, b = {}) req(:post, p, b) end
  def get(p) req(:get, p) end
  def signup() post('/api/signup', h: @h, pw: 'password123', adult: true, terms: true) end
  def public_of(h) get('/api/state')[1]['users'].find { |u| u['h'] == h }&.dig('public') end
end
def admin
  u = URI("#{BASE}/api/admin"); q = Net::HTTP::Get.new(u); q['X-Admin-Token'] = 'adm'
  JSON.parse(Net::HTTP.start(u.host, u.port) { |http| http.request(q) }.body)
end
def friends(a, b) a.post('/api/friend', to: b.h, action: 'request'); b.post('/api/friend', to: a.h, action: 'accept') end
def app_json() JSON.parse(File.read(File.join($dir, 'data', 'app.json'))) end
$dir = dir

$pass = $fail = 0
def t(name)
  yield
  $pass += 1; puts "PASS #{name}"
rescue StandardError => e
  $fail += 1; puts "FAIL #{name}: #{e.message[0, 400]}"
end
def check(c, m = 'failed') raise m.to_s unless c end

40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
ca, cb, cc, cd = %w[ct_amy ct_bo ct_cy ct_dee].map { |h| Who.new(h).tap(&:signup) }

t('link email + phone: you see them masked; nothing raw is stored') {
  _, j = ca.post('/api/contact/set', email: ' Amy.Test@Example.com ', phone: '(512) 555-0142')
  raw = File.read(File.join($dir, 'data', 'app.json'))
  check(j['email'] == 'a•••@example.com' && j['phone'] == '•••-•••-0142' && j['find'] == false, j)
  check(!raw.include?('amy.test') && !raw.include?('5550142'), 'raw contact in app.json')
  check(File.stat(File.join($dir, 'data', 'contact_key')).mode & 0o777 == 0o600, 'key file mode')
}
t('not findable until they opt in') {
  _, j = cb.post('/api/contact/match', contacts: [{ emails: ['amy.test@example.com'] }])
  check(j['found'] == [], j)
}
t('opted in: found by exact email (any case) and by phone in any format, with the contact position') {
  ca.post('/api/contact/set', find: true)
  _, j = cb.post('/api/contact/match', contacts: [{ emails: ['nobody@x.com'] }, { emails: ['AMY.TEST@example.com'] }, { phones: ['512-555-0142'] }])
  f = j['found']
  check(f.size == 1 && f[0]['h'] == 'ct_amy' && f[0]['i'].sort == [1, 2] && f[0]['friend'] == false, j)
}
t('a different address or a partial number finds nobody') {
  _, j = cb.post('/api/contact/match', contacts: [{ emails: ['amy.test@example.co'] }, { phones: ['555-0142'] }])
  check(j['found'] == [], j)
}
t('other people never see the email or phone, even masked') {
  st = cb.get('/api/state')[1]
  u = st['users'].find { |x| x['h'] == 'ct_amy' }
  check(u && !u.key?('contact') && !JSON.generate(st).include?('•••-•••-0142') && !JSON.generate(st).include?('a•••@'), u)
}
t('blocking hides you from their contact search (both ways)') {
  ca.post('/api/block', who: 'ct_cy', on: true)
  _, j = cc.post('/api/contact/match', contacts: [{ emails: ['amy.test@example.com'] }])
  check(j['found'] == [], j)
}
t('turning finding off, or unlinking, stops matches') {
  ca.post('/api/contact/set', find: false)
  _, j1 = cb.post('/api/contact/match', contacts: [{ emails: ['amy.test@example.com'] }])
  ca.post('/api/contact/set', find: true); ca.post('/api/contact/set', email: '')
  _, j2 = cb.post('/api/contact/match', contacts: [{ emails: ['amy.test@example.com'] }, { phones: ['5125550142'] }])
  check(j1['found'] == [] && j2['found'].map { |x| x['h'] } == ['ct_amy'], [j1, j2])
}
t('bad input is refused with a clear message') {
  c1, j1 = cd.post('/api/contact/set', email: 'not-an-email')
  c2, j2 = cd.post('/api/contact/set', phone: '12')
  check(c1 == 400 && j1['error'] =~ /email/ && c2 == 400 && j2['error'] =~ /area code/, [c1, j1, c2, j2])
}
t('guests can not search contacts') {
  code, = Who.new('guest').post('/api/contact/match', contacts: [{ phones: ['5125550142'] }])
  check(code == 401, code)
}
t('deleting the account removes the link') {
  cd.post('/api/contact/set', phone: '737 555 0199', find: true)
  _, j1 = cb.post('/api/contact/match', contacts: [{ phones: ['7375550199'] }])
  cd.post('/api/account/delete', pw: 'password123')
  _, j2 = cb.post('/api/contact/match', contacts: [{ phones: ['7375550199'] }])
  check(j1['found'].size == 1 && j2['found'] == [], [j1, j2])
}
t('contact search is rate-limited') {
  codes = 12.times.map { cc.post('/api/contact/match', contacts: [{ phones: ['5125550000'] }])[0] }
  check(codes.include?(429), codes)
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
