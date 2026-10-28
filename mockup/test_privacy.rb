# Privacy and safety fixes against a throwaway copy of the server with moderation ON and a fake Claude that can be
# switched off (no internet, no real Claude): ruby test_privacy.rb
# Chat photos / voice notes only for the people in the chat, moderation reads the whole text, profile answers that
# couldn't be checked stay hidden until a re-check passes, and deleting an account takes its votes and reports along.
require 'webrick'; require 'json'; require 'net/http'; require 'uri'; require 'tmpdir'; require 'fileutils'

PORT = 8806; EV_PORT = 9918
BASE = "http://127.0.0.1:#{PORT}"

ev = WEBrick::HTTPServer.new(Port: EV_PORT, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
ev.mount_proc('/api/events') { |_q, r| r['Content-Type'] = 'application/json'; r.body = JSON.generate(count: 0, events: []) }
Thread.new { ev.start }

dir = Dir.mktmpdir('sq-privacy-test')
FileUtils.cp(Dir[File.join(__dir__, '*.{rb,md,json,html}')], dir)
FileUtils.mkdir_p(File.join(dir, 'data')); File.write(File.join(dir, 'data', 'app.json'), '{}')
log = File.join(dir, 'server.log')
DOWN = File.join(dir, 'claude_down')            # exists = Claude can't be reached
CHECKED = File.join(dir, 'checked.txt')         # one line per text Claude was shown: its length
# a stand-in for Claude Code: text checks block anything with BADWORD; everything else gets an empty reply
FAKE = File.join(dir, 'fake_claude')
File.write(FAKE, "#!/usr/bin/env ruby\nrequire 'json'\npr = $stdin.read\nexit 1 if File.exist?(#{DOWN.inspect})\n" \
  "if (t = pr[/Text to check:\\n(\".*\")\\nGive a verdict/m, 1]) then t = JSON.parse(t)\n" \
  "  File.open(#{CHECKED.inspect}, 'a') { |f| f.puts t.size }\n" \
  "  bad = t.include?('BADWORD'); puts JSON.generate(type: 'result', structured_output: { verdict: bad ? 'block' : 'allow', reason: bad ? 'That word is not allowed here.' : 'ok' }, duration_ms: 1, total_cost_usd: 0); exit end\n" \
  "puts '{\"structured_output\":{\"say\":\"ok\",\"expression\":\"happy\",\"actions\":[]},\"duration_ms\":1,\"total_cost_usd\":0}'\n")
File.chmod(0o755, FAKE)
pid = spawn({ 'PORT' => PORT.to_s, 'SQ_MODERATE' => '1', 'SQ_DEMO' => '0', 'SQ_PHOTO_SCREEN' => '0', 'SQ_PLACES_FILE' => 'test_places.json',
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
pa, pb, pc, pd = %w[pv_amy pv_bo pv_cy pv_dee].map { |h| Who.new(h).tap(&:signup) }
friends(pa, pb); friends(pa, pc)   # dee is signed in but no one's friend

t('chat photo: the other person sees it; a signed-in stranger and a guest get 404') {
  jpg = 'data:image/jpeg;base64,' + ["\xFF\xD8\xFF\xE0".b + 'x' * 300].pack('m0')
  _, j = pa.post('/api/dm/send', to: 'pv_bo', img: jpg)
  url = j['msg']['img']
  codes = [pa.get(url)[0], pb.get(url)[0], pd.get(url)[0], pc.get(url)[0], Net::HTTP.get_response(URI("#{BASE}#{url}")).code.to_i]
  check(url && codes == [200, 200, 404, 404, 404], [url, codes])
}
t('group chat photo: members see it; someone who leaves stops seeing it') {
  _, g = pa.post('/api/chat/new', members: %w[pv_bo pv_cy], name: 'Plans')
  _, j = pa.post('/api/dm/send', to: g['with'], img: 'data:image/jpeg;base64,' + ["\xFF\xD8\xFF\xE0".b + 'y' * 300].pack('m0'))
  url = j['msg']['img']
  before = [pb.get(url)[0], pc.get(url)[0], pd.get(url)[0]]
  pc.post('/api/chat/edit', id: g['with'], leave: true)
  check(before == [200, 200, 404] && pc.get(url)[0] == 404 && pb.get(url)[0] == 200, [before, pc.get(url)[0]])
}
t('voice note: its uploader can play it before sending, no one else; after sending, the chat can') {
  u = URI("#{BASE}/api/dm/voice")
  cookie = pa.instance_variable_get(:@c)
  r = Net::HTTP.start(u.host, u.port) { |http| q = Net::HTTP::Post.new(u, 'Content-Type' => 'audio/mp4', 'Cookie' => "sq_s=#{cookie}"); q.body = 'a' * 5000; http.request(q) }
  id = JSON.parse(r.body)['id']
  pre = [pa.get("/dm-aud/#{id}")[0], pb.get("/dm-aud/#{id}")[0]]
  pa.post('/api/dm/send', to: 'pv_bo', aud: id)
  post = [pb.get("/dm-aud/#{id}")[0], pd.get("/dm-aud/#{id}")[0]]
  check(id && pre == [200, 404] && post == [200, 404], [id, pre, post])
}
t('moderation reads the whole post: a bad word after the first 600 characters is caught') {
  c, j = pa.post('/api/wall/post', t: ('fine words ' * 140) + 'BADWORD', vis: 'everyone')
  sizes = File.readlines(CHECKED).map(&:to_i)
  check(c == 403 && sizes.max > 1500, [c, j, sizes.last(3)])
}
t('profile saved while Claude is down: the owner sees it, others don\'t, admin lists it') {
  File.write(DOWN, '1')
  c, = pb.post('/api/profile', public: { 'hometown' => 'Lubbock', 'artists' => ['Khruangbin'] })
  mine, theirs = pb.public_of('pv_bo'), pa.public_of('pv_bo')
  held = admin.dig('unreviewed', 'profiles').to_a.map { |x| x['h'] }
  check(c == 200 && mine['hometown'] == 'Lubbock' && theirs == {} && held.include?('pv_bo'), [c, mine, theirs, held])
}
t('…when Claude is back the re-check passes it and everyone sees it') {
  File.delete(DOWN)
  ok = 20.times.any? { sleep 0.5; pa.public_of('pv_bo').to_h['hometown'] == 'Lubbock' }
  check(ok && admin.dig('unreviewed', 'profiles').to_a.none? { |x| x['h'] == 'pv_bo' }, pa.public_of('pv_bo'))
}
t('a held profile that fails the re-check stays hidden and its owner is told (once)') {
  File.write(DOWN, '1')
  pc.post('/api/profile', public: { 'hometown' => 'BADWORD town' })
  File.delete(DOWN)
  told = 20.times.any? { sleep 0.5; pc.post('/api/notifs')[1]['notifs'].any? { |n| n['t'] == 'mod' } }
  sleep 2.5
  n = pc.post('/api/notifs')[1]['notifs'].count { |x| x['t'] == 'mod' }
  check(told && n == 1 && pa.public_of('pv_cy') == {} && pc.public_of('pv_cy')['hometown'] == 'BADWORD town', [told, n, pa.public_of('pv_cy')])
}
t('a profile saved while Claude works and passes shows at once; unchanged saves keep a hold') {
  pd.post('/api/profile', public: { 'hometown' => 'Austin' })
  shown = pa.public_of('pv_dee')['hometown'] == 'Austin'
  pc.post('/api/profile', public: { 'hometown' => 'BADWORD town' })   # same text again: still held
  check(shown && pa.public_of('pv_cy') == {}, [shown, pa.public_of('pv_cy')])
}
t('deleting an account removes its bar-food reports and ranking suggestions') {
  pd.post('/api/place/barfood', id: 'n1002', food: 'yes', close: '23:00')
  pd.post('/api/rankings/suggest', k: 'pizza', name: 'Dee Pizza', why: 'mine')
  before = app_json
  pd.post('/api/account/delete', pw: 'password123', confirm: 'pv_dee')
  after = app_json
  had = before.dig('barfood', 'n1002', 'pv_dee') && before['rank_suggest'].to_a.any? { |s| s['h'] == 'pv_dee' }
  check(had && !after.dig('barfood', 'n1002').to_h.key?('pv_dee') && after['rank_suggest'].to_a.none? { |s| s['h'] == 'pv_dee' } && !after['users'].key?('pv_dee'),
        [had, after['barfood'], after['rank_suggest']])
}

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
