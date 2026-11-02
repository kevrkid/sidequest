# "I'm out tonight" (outnight.rb) against a throwaway copy of the server: ruby test_outnight.rb
# Friends see your status and get one heads-up a night; strangers and blocked people see nothing; "I'm down" tells
# you; only listed picks and hot spots are accepted; staying in hides it without pinging again; deleting an account
# takes it away.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'; require 'time'

PORT = 8810; EV_PORT = 9922
BASE = "http://127.0.0.1:#{PORT}"
SOON = (Time.now + 3 * 86_400).utc.iso8601
EVENTS = [{ uid: 'pk1', title: 'Pickup basketball at the Y', category: 'pickup', start: SOON, venue: 'YMCA', lat: 30.27, lng: -97.74 },
          { uid: 'tr1', title: 'Tuesday trivia night', category: 'other', start: SOON, venue: 'Some Pub', lat: 30.27, lng: -97.74 }]

ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: EVENTS.size, events: EVENTS) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-outnight-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
FileUtils.mkdir_p(File.join(dir, 'data')); File.write(File.join(dir, 'data', 'app.json'), '{}')
log = File.join(dir, 'server.log')
FAKE = File.join(dir, 'fake_claude')
File.write(FAKE, "#!/bin/sh\necho '{\"structured_output\":{\"say\":\"ok\",\"expression\":\"happy\",\"actions\":[]},\"duration_ms\":1,\"total_cost_usd\":0}'\n")
File.chmod(0o755, FAKE)
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PHOTO_SCREEN' => '0', 'SQ_WARM' => '0', 'SQ_PLACES_FILE' => 'test_places.json',
              'SQ_OUTDOORS_FILE' => 'test_outdoors.json', 'SQ_SIGHTS_FILE' => 'test_sights.json', 'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}",
              'SQ_LIVEKIT_URL' => nil, 'SQ_GOOGLE_PLACES_KEY' => nil, 'SQ_GOOGLE_TTS_KEY' => nil,
              'SQ_ENGINE' => 'cli', 'CLAUDE_BIN' => FAKE, 'SQ_USE_API_KEY' => nil },
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
  def outn() get('/api/state')[1].dig('v2', 'outn') end
end

$pass = $fail = 0
def t(name)
  yield
  $pass += 1; puts "PASS #{name}"
rescue StandardError => e
  $fail += 1; puts "FAIL #{name}: #{e.message[0, 400]}"
end
def check(c, m = 'failed') raise m.to_s unless c end
def friends(a, b) a.post('/api/friend', to: b.h, action: 'request'); b.post('/api/friend', to: a.h, action: 'accept') end

40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
amy, bo, cy, dee = %w[on_amy on_bo on_cy on_dee].map { |h| Who.new(h).tap(&:signup) }
friends(amy, bo); friends(amy, dee)
guest = Who.new('guest')

t('only picks from the list, a known area, and signed in') {
  c1, = amy.post('/api/out', acts: ['heroin'])
  c2, = amy.post('/api/out', acts: ['drinks'], zone: 'nowhere')
  c3, = guest.post('/api/out', acts: ['drinks'])
  check(c1 == 400 && c2 == 400 && c3 == 401, [c1, c2, c3])
}
t('going out: you see it, friends see it, a stranger does not') {
  c, j = amy.post('/api/out', acts: %w[drinks pool dancing karaoke comedy], when: '22', zone: 'rainey')
  bo_v = bo.outn; cy_v = cy.outn
  f = bo_v['friends'].find { |x| x['h'] == 'on_amy' }
  check(c == 200 && j['me']['acts'] == %w[drinks pool dancing karaoke] && j['me']['zname'] == 'Rainey Street' && f && f['when'] == '22' &&
        f['zname'] == 'Rainey Street' && cy_v['friends'].empty?, [c, j, bo_v, cy_v])
}
t('friends get one heads-up; editing it does not ping again') {
  amy.post('/api/out', acts: %w[food], when: 'now')
  n = bo.post('/api/notifs')[1]
  list = (n['notifs'] || n['list'] || n).select { |x| x['t'] == 'out' }
  check(list.size == 1 && list[0]['ref'] == 'o:on_amy' && list[0]['text'].include?('out tonight'), n)
}
t("I'm down: they hear about it and see who; friends see the count") {
  c, j = bo.post('/api/out/down', h: 'on_amy')
  me = amy.outn['me']; n = amy.post('/api/notifs')[1]
  downs = (n['notifs'] || n['list'] || n).select { |x| x['t'] == 'down' && x['ref'] == 'o:on_amy' }
  dee_v = dee.outn['friends'].find { |x| x['h'] == 'on_amy' }
  check(c == 200 && j['friends'][0]['mine'] == true && me['down'] == ['on_bo'] && downs.size == 1 && dee_v['downs'] == 1 && dee_v['mine'] == false, [j, me, downs, dee_v])
}
t("a stranger can't say they're down") {
  c, = cy.post('/api/out/down', h: 'on_amy')
  check(c == 400, c)
}
t('taking it back') {
  bo.post('/api/out/down', h: 'on_amy', on: false)
  check(amy.outn['me']['down'].empty?, amy.outn)
}
t('blocking hides it') {
  dee.post('/api/block', who: 'on_amy', on: true)
  check(dee.outn['friends'].none? { |x| x['h'] == 'on_amy' }, dee.outn)
}
t('staying in hides it, and going out again the same night does not ping twice') {
  amy.post('/api/out/off')
  gone = bo.outn['friends'].empty? && amy.outn['me'].nil?
  amy.post('/api/out', acts: %w[chill])
  n = bo.post('/api/notifs')[1]
  list = (n['notifs'] || n['list'] || n).select { |x| x['t'] == 'out' }
  check(gone && list.size == 1 && bo.outn['friends'].size == 1, [gone, list.size])
}
t('deleting an account takes its status and its "down"s away') {
  bo.post('/api/out/down', h: 'on_amy')
  bo.post('/api/account/delete', pw: 'password123', confirm: true)
  check(amy.outn['me']['down'].empty?, amy.outn)
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
