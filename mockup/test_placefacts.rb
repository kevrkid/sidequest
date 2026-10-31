# What's here (placefacts.rb) against a throwaway copy of the server (no internet, no real Claude): ruby test_placefacts.rb
# People say what a place or park has (yes / no); a fact shows when more say yes than no; one answer set per person;
# unknown places and keys are refused; guests can read but not answer; the search index lists confirmed facts;
# deleting an account takes its answers along.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8808; EV_PORT = 9920
BASE = "http://127.0.0.1:#{PORT}"

ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: 0, events: []) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-placefacts-test')
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
fa, fb, fc = %w[pf_amy pf_bo pf_cy].map { |h| Who.new(h).tap(&:signup) }
guest = Who.new('guest')

t('a bar: yes answers show, a no from one person does not outweigh two yeses') {
  fa.post('/api/place/facts/set', id: 'n1002', facts: { pool: 'y', dj: 'y', busy_fsn: 'y' })
  fb.post('/api/place/facts/set', id: 'n1002', facts: { pool: 'y', dj: 'n' })
  _, j = guest.get('/api/place/facts?id=n1002')
  check(j['facts'].keys.sort == %w[busy_fsn pool] && j['facts']['pool'] == [2, 0] && j['no'] == ['dj'] && j['people'] == 2, j)
}
t('one answer set per person: changing your answer replaces it; "" takes it back') {
  fb.post('/api/place/facts/set', id: 'n1002', facts: { pool: 'n' })
  _, j1 = guest.get('/api/place/facts?id=n1002')
  fb.post('/api/place/facts/set', id: 'n1002', facts: { pool: '', dj: '' })
  _, j2 = fb.get('/api/place/facts?id=n1002')
  check(j1['facts'].key?('pool') == false && j2['facts']['pool'] == [1, 0] && j2['people'] == 1 && j2['mine'] == {}, [j1, j2])
}
t('you get your own answers back') {
  _, j = fa.get('/api/place/facts?id=n1002')
  check(j['mine'] == { 'pool' => 'y', 'dj' => 'y', 'busy_fsn' => 'y' }, j)
}
t('parks work too (outdoors data)') {
  c, j = fc.post('/api/place/facts/set', id: 'w1', facts: { restrooms: 'y', dogpark: 'y' })
  check(c == 200 && j['facts'].keys.sort == %w[dogpark restrooms], [c, j])
}
t('unknown place, unknown key and guests are refused') {
  c1, = fa.post('/api/place/facts/set', id: 'nope', facts: { pool: 'y' })
  c2, j2 = fa.post('/api/place/facts/set', id: 'n1002', facts: { hottub: 'y' })
  c3, = guest.post('/api/place/facts/set', id: 'n1002', facts: { pool: 'y' })
  c4, = fa.post('/api/place/facts/set', id: 'n1002', facts: { pool: 'maybe' })
  check(c1 == 400 && c2 == 400 && c3 == 401 && c4 == 400, [c1, c2, j2, c3, c4])
}
t('the search index lists confirmed facts by place') {
  _, j = guest.get('/api/place/facts/index')
  check(j['facts']['pool'] == ['n1002'] && j['facts']['dj'] == ['n1002'] && j['facts']['restrooms'] == ['w1'] && !j['facts'].key?('darts'), j)   # bo took back the DJ "no
}
t('Bars with pool tables / games: only bars people said have them (or whose name says so)') {
  sleep 0.1
  _, pool = guest.get('/api/places?cat=pool&limit=80')
  _, games = guest.get('/api/places?cat=bargames&limit=80')
  pool_ids = pool['places'].map { |x| x['id'] }; game_ids = games['places'].map { |x| x['id'] }
  check(pool_ids.include?('n1002') && !pool_ids.include?('n1003') && game_ids.include?('n1002') && pool['label'] == 'Bars with pool tables', [pool_ids, game_ids, pool['label']])
}
t("Explore's suggestions: a check-in shows up as a place you've been, with its food and kind") {
  c0, g = guest.get('/api/foryou')
  fb.post('/api/checkin', k: 'place', id: 'n1001')
  _, j = fb.get('/api/foryou')
  check(c0 == 200 && g.key?('ranks') && !g.key?('visited') && j['visited'].include?('n1001') && j['kinds'].key?('food truck') && j['foods'].keys.any? { |f| f =~ /mexican|food truck/ }, [g.keys, j])
}
t('deleting an account takes its answers along') {
  fc.post('/api/account/delete', pw: 'password123')
  _, j = guest.get('/api/place/facts?id=w1')
  check(j['facts'] == {} && j['people'] == 0, j)
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
