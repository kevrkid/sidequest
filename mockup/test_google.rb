# Google Places details in server.rb, against a fake Google API (no key, no internet): ruby test_google.rb
# Runs a throwaway copy of the server on :8794 with its own empty data folder, so your real data is untouched.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8794; G_PORT = 9913
BASE = URI("http://127.0.0.1:#{PORT}")

$g = []   # [path, field mask, api key, body] for every Google call
g = WEBrick::HTTPServer.new(Port: G_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
g.mount_proc('/v1') do |req, res|
  body = req.body ? JSON.parse(req.body) : nil
  $g << [req.path, req['X-Goog-FieldMask'], req['X-Goog-Api-Key'], body]
  res['Content-Type'] = 'application/json'
  res.body = JSON.generate(
    if req.path.end_with?('places:searchText')
      if body['textQuery'] =~ /Night Noodle/   # one right next door, one across town with the same name
        { places: [{ id: 'far_away', location: { latitude: 30.40, longitude: -97.70 } },
                   { id: 'g_noodle', location: { latitude: 30.26892, longitude: -97.73502 } }] }
      else { places: [] }
      end
    else
      { rating: 4.6, userRatingCount: 1234, priceLevel: 'PRICE_LEVEL_MODERATE', googleMapsUri: 'https://maps.google.com/?cid=1',
        currentOpeningHours: { openNow: true, weekdayDescriptions: ['Monday: 10:00 AM – 4:00 AM'] } }
    end)
end
# fake tokeninfo: the "ID token" is just which person and how it should look
TOKENS = { 'amy' => { sub: '1000001', given_name: 'Amy' }, 'amy-other-app' => { sub: '1000001', aud: 'someone-else.apps.googleusercontent.com' },
           'unverified' => { sub: '1000002', email_verified: 'false' } }
g.mount_proc('/tokeninfo') do |req, res|
  t = TOKENS[req.query['id_token']]
  res['Content-Type'] = 'application/json'
  next (res.status = 400; res.body = '{"error":"invalid_token"}') unless t
  res.body = JSON.generate({ iss: 'https://accounts.google.com', aud: 'test-client.apps.googleusercontent.com', exp: (Time.now.to_i + 3600).to_s,
                             email: 'amy@example.com', email_verified: 'true' }.merge(t))
end
$tts = []   # fake Text-to-Speech: records what was asked, answers with a few fake MP3 bytes
g.mount_proc('/v1/text:synthesize') do |req, res|
  $tts << [URI.decode_www_form(req.query_string.to_s).to_h['key'], JSON.parse(req.body)]   # (req.query reads a POST's body)
  res['Content-Type'] = 'application/json'
  res.body = JSON.generate(audioContent: ['ID3fake-mp3'].pack('m0'))
end
Thread.new { g.start }

dir = $dir = Dir.mktmpdir('sq-google-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json}')], dir)
log = File.join(dir, 'server.log')
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_GOOGLE_PLACES_KEY' => 'gkey-test', 'SQ_GOOGLE_API_URL' => "http://127.0.0.1:#{G_PORT}/v1",
              'SQ_GOOGLE_DAILY' => '2', 'SQ_MODERATE' => '0', 'SQ_DEMO' => '0', 'SQ_PLACES_FILE' => 'test_places.json',
              'SQ_LIVEKIT_URL' => nil, 'SQ_GOOGLE_CLIENT_ID' => 'test-client.apps.googleusercontent.com', 'SQ_GOOGLE_SIGNIN' => '1',
              'SQ_GOOGLE_TOKENINFO_URL' => "http://127.0.0.1:#{G_PORT}/tokeninfo",
              'SQ_GOOGLE_TTS_KEY' => 'tts-key', 'SQ_TTS_URL' => "http://127.0.0.1:#{G_PORT}/v1/text:synthesize", 'SQ_TTS_DAILY_CHARS' => '60' },
            'ruby', 'server.rb', chdir: dir, out: log, err: log)
at_exit { Process.kill('TERM', pid) rescue nil; FileUtils.rm_rf(dir) }

def get(path)
  r = Net::HTTP.get_response(URI("#{BASE}#{path}"))
  [r.code.to_i, (JSON.parse(r.body) rescue {})]
end

def post(path, body)
  r = Net::HTTP.post(URI("#{BASE}#{path}"), JSON.generate(body), 'Content-Type' => 'application/json')
  [r.code.to_i, (JSON.parse(r.body) rescue {}), r['Set-Cookie'].to_s[/sq_s=([^;]+)/, 1]]
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

t('the app is told Google is on') {
  check(Net::HTTP.get(URI("#{BASE}/config.js")).include?('"google":true'), 'config.js has no google flag')
}
t('a tapped place gets rating, price, open now and hours, matched to the right spot') {
  code, j = get('/api/place/google?id=n1009')
  check(code == 200 && j['rating'] == 4.6 && j['count'] == 1234 && j['price'] == '$$' && j['open_now'] == true, j.inspect)
  check(j['hours'] == ['Monday: 10:00 AM – 4:00 AM'] && j['maps'].start_with?('https://maps.google.com'), j.inspect)
  detail = $g.find { |p, *_| p.end_with?('/places/g_noodle') } or raise "fetched the wrong place: #{$g.map(&:first)}"
  check(detail[2] == 'gkey-test' && detail[1].include?('rating') && detail[1].include?('currentOpeningHours'), detail.inspect)
}
t('the match search asks Google for ids only (its free tier), inside a box around the place') {
  s = $g.find { |p, *_| p.end_with?('places:searchText') }
  box = s[3].dig('locationRestriction', 'rectangle') or raise "not limited to the area: #{s[3].keys}"
  check(s[1] == 'places.id,places.location' && box['low']['latitude'] < 30.26890 && box['high']['latitude'] > 30.26890, s.inspect)
}
t('only the Google place id is kept; no ratings or hours are stored') {
  $g.clear
  get('/api/place/google?id=n1009')
  check($g.none? { |p, *_| p.end_with?('places:searchText') }, 'searched again instead of reusing the id')
  saved = Dir[File.join($dir, 'data', '*.json')].map { |f| File.read(f) }.join
  check(saved.include?('g_noodle') && !saved.include?('4.6') && !saved.include?('10:00 AM'), 'stored more than the id')
}
t('no match on Google: says so, and does not search again') {
  _, j = get('/api/place/google?id=n1006')
  $g.clear
  _, j2 = get('/api/place/google?id=n1006')
  check(j['none'] == true && j2['none'] == true && $g.empty?, "#{j} #{j2} #{$g.map(&:first)}")
}
t('the daily cap stops paid lookups') {
  code, j = get('/api/place/google?id=n1009')   # 3rd details lookup with SQ_GOOGLE_DAILY=2
  check(code == 429 && j['error'] =~ /paused/, "#{code} #{j}")
}

# ---- Scout's voice
t('the app is told Scout has a Google voice') {
  check(Net::HTTP.get(URI("#{BASE}/config.js")).include?('"voice":true'), 'no voice flag')
}
t('Scout speaks with the chosen Google voice; the key never reaches the phone') {
  code, j, = post('/api/scout/voice', text: 'Lets go explore!', voice: 'aoede')
  k, body = $tts.last
  check(code == 200 && j['audio'].unpack1('m') == 'ID3fake-mp3' && k == 'tts-key' && body['voice']['name'] == 'en-US-Chirp3-HD-Aoede' &&
        body['input']['text'] == 'Lets go explore!' && !Net::HTTP.get(URI("#{BASE}/config.js")).include?('tts-key'), "#{code} #{body}")
}
t('the same words again come from the cache, not Google') {
  n = $tts.size; post('/api/scout/voice', text: 'Lets go explore!', voice: 'aoede')
  check($tts.size == n, 'asked Google again')
}
t("the day's speech cap stops new speech") {
  c1, = post('/api/scout/voice', text: 'x' * 30)
  c2, j2, = post('/api/scout/voice', text: 'y' * 30)
  check(c1 == 200 && c2 == 429, "#{c1} #{c2} #{j2}")
}

# ---- Sign in with Google
$ticket = nil
t('a new Google account gets a ticket to pick a handle (and a suggestion), not a session') {
  code, j, cookie = post('/api/google', credential: 'amy')
  $ticket = j['ticket']
  check(code == 200 && j['new'] && $ticket && j['suggest'] == 'amy' && !cookie, "#{code} #{j}")
}
t('Google tokens for another app, or unverified emails, are refused') {
  c1, = post('/api/google', credential: 'amy-other-app'); c2, = post('/api/google', credential: 'unverified'); c3, = post('/api/google', credential: 'junk')
  check([c1, c2, c3] == [401, 401, 401], [c1, c2, c3].inspect)
}
t('sign-up with the ticket: no password, still needs 18+ and Terms') {
  c0, j0, = post('/api/signup', h: 'google_amy', google: $ticket, adult: true, terms: false)
  code, j, cookie = post('/api/signup', h: 'google_amy', google: $ticket, adult: true, terms: true)
  check(c0 == 400 && j0['error'] =~ /Terms/ && code == 200 && cookie, "#{c0} #{j0} #{code} #{j}")
}
t('only the Google account id is stored: no email, no password') {
  sleep 0.3
  d = JSON.parse(File.read(File.join($dir, 'data', 'app.json')))
  u = d['users']['google_amy']
  check(d['google_ids'] == { '1000001' => 'google_amy' } && u['google'] && !u.key?('pw') && !File.read(File.join($dir, 'data', 'app.json')).include?('amy@example.com'), u.inspect)
}
t('Continue with Google next time signs straight in') {
  code, j, cookie = post('/api/google', credential: 'amy')
  check(code == 200 && j['ok'] && j['h'] == 'google_amy' && cookie, "#{code} #{j}")
}
t('a made-up or reused ticket does not work') {
  c1, j1, = post('/api/signup', h: 'faker', google: "1000009.#{Time.now.to_i + 600}.#{'0' * 64}", adult: true, terms: true)
  c2, j2, = post('/api/signup', h: 'amy_again', google: $ticket, adult: true, terms: true)
  check(c1 == 400 && j1['error'] =~ /timed out/ && c2 == 400 && j2['error'] =~ /already has/, "#{j1} #{j2}")
}
t('a Google-only account cannot be opened with a password') {
  code, = post('/api/login', h: 'google_amy', pw: '')
  check(code == 401, code.to_s)
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
