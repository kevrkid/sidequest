# Lifestyle score (lifestyle.rb) against a throwaway copy of the server (no internet, no real Claude): ruby test_lifestyle.rb
# What you do moves the right traits (a park → outdoors, a pickup game → active, bars → drinking, a club late → night
# owl); each person sees only their own; guests can't ask; the "weeks ago" points don't count what happened since;
# cannabis and diet are never worked out from activity.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'; require 'time'

PORT = 8809; EV_PORT = 9921
BASE = "http://127.0.0.1:#{PORT}"
SOON = (Time.now + 3 * 86_400).utc.iso8601
EVENTS = [{ uid: 'pk1', title: 'Pickup basketball at the Y', category: 'pickup', start: SOON, venue: 'YMCA', lat: 30.27, lng: -97.74 },
          { uid: 'tr1', title: 'Tuesday trivia night', category: 'other', start: SOON, venue: 'Some Pub', lat: 30.27, lng: -97.74 }]

ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: EVENTS.size, events: EVENTS) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-lifestyle-test')
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
  def style() get('/api/lifestyle')[1] end
end

$pass = $fail = 0
def t(name)
  yield
  $pass += 1; puts "PASS #{name}"
rescue StandardError => e
  $fail += 1; puts "FAIL #{name}: #{e.message[0, 400]}"
end
def check(c, m = 'failed') raise m.to_s unless c end

40.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
amy, bo = %w[ls_amy ls_bo].map { |h| Who.new(h).tap(&:signup) }
guest = Who.new('guest')

t('a new account starts at zero on every trait, with past points') {
  j = amy.style
  check(j['traits'].keys.sort == %w[active culture drink explorer fan foodie indoor night outdoors].sort &&
        j['traits'].values.all? { |v| v['a'].zero? } && j['total'].zero? && j['past'].size == 5, j)
}
t('guests are asked to sign in') {
  c, = guest.get('/api/lifestyle')
  check(c == 401, c)
}
t('a park check-in counts toward outdoors (and exploring), with its name as the reason') {
  amy.post('/api/checkin', k: 'area', id: 'w1')
  j = amy.style
  check(j['traits']['outdoors']['a'] > 30 && j['traits']['outdoors']['why'] == ['Test Greenbelt'] && j['traits']['explorer']['a'] > 0 &&
        j['traits']['drink']['a'].zero?, j['traits'])
}
t('going to a pickup game counts toward active; a trivia night toward indoors') {
  amy.post('/api/rsvp', id: 'pk1', status: 'going')
  amy.post('/api/rsvp', id: 'tr1', status: 'interested')
  j = amy.style
  check(j['traits']['active']['a'] > 30 && j['traits']['indoor']['a'] > 0 && j['traits']['fan']['a'].zero?, j['traits'])
}
t('bars and a club count toward drinking and night owl; a food truck toward foodie') {
  amy.post('/api/checkin', k: 'place', id: 'n1002')
  amy.post('/api/checkin', k: 'place', id: 'n1008')
  amy.post('/api/checkin', k: 'place', id: 'n1003')
  amy.post('/api/checkin', k: 'place', id: 'n1001')
  j = amy.style
  check(j['traits']['drink']['a'] > 40 && j['traits']['night']['a'] > 20 && j['traits']['foodie']['a'] > 20 &&
        j['traits']['drink']['why'].include?('Sixth Street Saloon'), j['traits'])
}
t('each person sees only their own') {
  j = bo.style
  check(j['total'].zero? && j['traits'].values.all? { |v| v['a'].zero? && v['why'].empty? }, j)
}
t("the weeks-ago points don't count what happened since") {
  j = amy.style
  check(j['total'] > 0 && j['past'].all? { |x| x['total'].zero? && x['a'].values.all?(&:zero?) } && j['past'].map { |x| x['at'] } == j['past'].map { |x| x['at'] }.sort, j['past'])
}
t('cannabis and diet are never worked out from activity') {
  j = amy.style
  check(!j['traits'].key?('cannabis') && !j['traits'].key?('diet'), j['traits'].keys)
}
t('taking back an RSVP takes it out of the score') {
  before = amy.style['traits']['active']['a']
  amy.post('/api/rsvp', id: 'pk1', status: nil)
  after = amy.style['traits']['active']['a']
  check(before > 0 && after.zero?, [before, after])
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
