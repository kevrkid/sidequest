# Pulse routes against a throwaway copy of the server (no internet, no Claude): ruby test_pulse_api.rb
# Vibe check from check-ins, stories and reports; facts; the night's pick with friends (and privacy); the media feed.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'; require 'time'

PORT = 8805; EV_PORT = 9917
BASE = "http://127.0.0.1:#{PORT}"
now = Time.now
EVENTS = [{ uid: 'pulse0000001', title: 'DJ Night', start: (now - 1800).iso8601, end: (now + 3 * 3600).iso8601, venue: 'Sixth Street Saloon',
            city: 'Austin', lat: 30.26718, lng: -97.7399, geo_precise: true, category: 'music' }]
ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: EVENTS.size, events: EVENTS) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-pulse-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
FileUtils.mkdir_p(File.join(dir, 'data'))
File.write(File.join(dir, 'data', 'app.json'), '{}')
log = File.join(dir, 'server.log')
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PLACES_FILE' => 'test_places.json', 'SQ_OUTDOORS_FILE' => 'test_outdoors.json',
              'SQ_SIGHTS_FILE' => 'test_sights.json', 'SQ_EVENTS_API' => "http://127.0.0.1:#{EV_PORT}", 'SQ_LIVEKIT_URL' => nil,
              'SQ_GOOGLE_PLACES_KEY' => nil, 'SQ_GOOGLE_TTS_KEY' => nil, 'SQ_PHOTO_SCREEN' => '0', 'SQ_PULSE_FILE' => File.join(dir, 'pulse.json'), 'SQ_PULSE_TICK_SECS' => '3',
              'TZ' => 'America/Chicago' },
            'ruby', 'server.rb', chdir: dir, out: log, err: log)
at_exit do
  begin
    Process.kill('TERM', pid); 30.times { break if Process.waitpid(pid, Process::WNOHANG); sleep 0.1 }
    Process.kill('KILL', pid) rescue nil
  rescue StandardError
    nil
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
end

$pass = $fail = 0
def t(name)
  r = yield
  $pass += 1; puts "PASS #{name}#{r.is_a?(String) ? "  [#{r}]" : ''}"
rescue => e
  $fail += 1; puts "FAIL #{name}: #{e.message[0, 400]}"
end
def check(c, m = 'failed') raise m.to_s unless c end

60.times { break if (Net::HTTP.get_response(URI("#{BASE}/api/health")) rescue nil); sleep 0.25 }
guest = Who.new(nil)
amy, bo, cy, dee, eve = %w[amy_p bo_p cy_p dee_p eve_p].map { |h| Who.new(h).tap(&:signup) }
[bo, dee].each { |f| amy.post('/api/friend', to: f.h, action: 'request'); f.post('/api/friend', to: amy.h, action: 'accept') }
BAR = 'n1002'   # Sixth Street Saloon in test_places.json, open 24/7

t('nothing going on: empty pulse, still answers guests') do
  c, r = guest.get('/api/pulse?lat=30.267&lng=-97.739')
  check(c == 200 && r['places'] == [] && r['trending'] == [], [c, r])
end

t('check-ins make a place show up, counted per person') do
  [bo, cy, dee, eve].each { |w| c, r = w.post('/api/checkin', k: 'place', id: BAR); check(c == 200, [w.h, c, r]) }
  _, r = guest.get('/api/pulse?lat=30.267&lng=-97.739')
  row = r['places'].find { |x| x['id'] == BAR } or raise r.inspect
  check(row['vibe']['people'] == 4 && row['vibe']['heat'] > 5 && row['vibe']['sure'] == 'high', row)
  "#{row['vibe']['e']} #{row['vibe']['label']}, #{row['vibe']['people']} people"
end

t('a public story there is proof, and its words describe the vibe') do
  c, r = bo.post('/api/story', story: { caption: 'DJ is going off, packed in here', lat: 30.26718, lng: -97.7399, place: 'Sixth Street Saloon', vis: 'everyone' })
  check(c == 200, [c, r])
  _, p = guest.get("/api/pulse/place?id=#{BAR}")
  check(p['proof'].any? { |m| m['t'] == 'story' && m['by'] == 'bo_p' }, p['proof'])
  check((p['vibe']['words'] & %w[DJ packed]).size == 2, p['vibe']['words'])
  p['vibe']['words'].join(', ')
end

t('place page: facts and tonight') do
  _, p = guest.get("/api/pulse/place?id=#{BAR}")
  f = p['facts']
  check(f['hours'].size == 24 && f['based_on'] && f['status'], f)
  check(p['events'].any? { |e| e['uid'] == 'pulse0000001' }, p['events'])
  _, club = guest.get('/api/pulse/place?id=n1003')
  check(club['facts']['last_call'] == 'Last call ~1:45 AM', club['facts'])
  [f['peak'], club['facts']['peak'], club['facts']['arrive']].compact.join(' · ')
end

t('vibe reports: members only, checked, and they move the level') do
  c, = guest.post('/api/pulse/vibe', id: BAR, v: 'packed')
  check(c == 401, c)
  c, = cy.post('/api/pulse/vibe', id: BAR, v: 'awesome')
  check(c == 400, c)
  c, = cy.post('/api/pulse/vibe', id: 'nope', v: 'packed')
  check(c == 400, c)
  c, r = cy.post('/api/pulse/vibe', id: BAR, v: 'packed', tags: %w[line cover hax])
  check(c == 200 && r['vibe']['key'] == 'packed' && r['vibe']['words'].include?('line'), [c, r])
  c, r = cy.post('/api/pulse/vibe', id: BAR, v: 'chill')   # a new report replaces your last one there
  check(c == 200 && r['vibe']['reports'] == 1 && r['vibe']['level'] < 0.6, r['vibe'])
  "#{r['vibe']['e']} #{r['vibe']['label']} (#{r['vibe']['level']})"
end

t('the pick: friends there by what they show, never by private check-ins') do
  c, r = amy.post('/api/pulse/pick', lat: 30.2672, lng: -97.7395, want: 'lively', kind: 'bars', hours: 3)
  check(c == 200 && r['pick'], [c, r])
  all = [r['pick'], r['plan_b'], *r['more']].compact
  saloon = all.find { |x| x['id'] == BAR } or raise "saloon not ranked: #{all.map { |x| x['name'] }}"
  why = saloon['why'].join(' | ')
  check(why.include?('@bo_p'), why)          # bo's public story is there
  check(!why.include?('@dee_p'), why)        # dee only checked in, with sharing off
  "#{r['pick']['name']}: #{r['pick']['why'].join(' · ')}"
end

t('opted-in check-ins do count as a friend being there') do
  dee.post('/api/quests/board', share: true)
  _, r = amy.post('/api/pulse/pick', lat: 30.2672, lng: -97.7395, want: 'lively', kind: 'bars', hours: 3)
  saloon = [r['pick'], r['plan_b'], *r['more']].compact.find { |x| x['id'] == BAR }
  check(saloon && saloon['why'].join(' ').include?('@dee_p'), saloon)
end

t('guests get a pick too (no taste, no friends)') do
  c, r = guest.post('/api/pulse/pick', lat: 30.2672, lng: -97.7395, want: 'chill', kind: 'food')
  check(c == 200 && r['pick'] && r['pick']['why'].none? { |x| x.include?('@') }, [c, r])
  "#{r['pick']['name']}: #{r['pick']['why'].join(' · ')}"
end

t('media feed: the story, from a busy place') do
  c, r = guest.get('/api/pulse/feed?lat=30.267&lng=-97.739')
  check(c == 200 && r['items'].first && r['items'].first['u'] == 'bo_p' && r['items'].first['place'] == 'Sixth Street Saloon', [c, r])
end

t('blocked people drop out of the feed') do
  amy.post('/api/block', who: 'bo_p')
  _, r = amy.get('/api/pulse/feed?lat=30.267&lng=-97.739')
  check(r['items'].none? { |m| m['u'] == 'bo_p' }, r['items'])
end

t('the hourly fold saves who was where (counts only, no names)') do
  sleep 4
  pj = JSON.parse(File.read(File.join(dir, 'pulse.json')))
  row = pj['p'][BAR] or raise pj.keys.inspect
  check(row['s'].max >= 4 && pj['w'].max >= 1, row)
  check(!File.read(File.join(dir, 'pulse.json')).include?('amy_p') && !File.read(File.join(dir, 'pulse.json')).include?('bo_p'), 'handles in pulse.json')
end

t('server log has no errors') do
  bad = File.read(log).lines.grep(/\[\/api\/pulse|NoMethodError|NameError|TypeError/)
  check(bad.empty?, bad.first(5).join)
end

puts "\n#{$pass} passed, #{$fail} failed"
exit($fail.zero? ? 0 : 1)
