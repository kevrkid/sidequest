# Tests the Anthropic API engine in server.rb against a fake API on :9911 (no key, no internet): ruby test_api.rb
require 'webrick'; require 'json'; require 'net/http'; require 'openssl'; require 'uri'
SRC = File.read(File.join(__dir__, 'server.rb'), encoding: 'utf-8')
ENV['SQ_USE_API_KEY'] = '1'; ENV['ANTHROPIC_API_KEY'] = 'test-key'; ENV['SQ_API_URL'] = 'http://127.0.0.1:9911/v1/messages'
schemas = SRC[/^PICKS_SCHEMA = .*?(?=^SCREEN_SYSTEM)/m] + SRC[/^SCREEN_SCHEMA = .*?\.to_json/m] + "\n" + SRC[/^SCOUT_SCHEMA = .*?\.to_json/m]
SCOUT_FACES = %w[happy calm]; SYSTEM = 'sys'; MODEL = 'sonnet'; TIMEOUT = 20
eval(schemas)
eval(SRC[/^USE_API_KEY = .*?(?=^# Run one headless)/m])

$mode = nil; $seen = []; $hits = 0
srv = WEBrick::HTTPServer.new(Port: 9911, Logger: WEBrick::Log.new('/dev/null'), AccessLog: [])
srv.mount_proc('/v1/messages') do |req, res|
  $hits += 1; $seen << [req.header, JSON.parse(req.body)]
  res['content-type'] = 'application/json'; res['request-id'] = 'req_test'
  usage = { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }
  case $mode
  when :ok
    out = { summary: 's', picks: (1..7).map { |i| { id: "e#{i}", match: 140, headline: 'h', reasons: ['r'], pitch: 'p' } } }
    res.body = JSON.generate(model: 'claude-sonnet-5-5', stop_reason: 'end_turn', usage: usage,
      content: [{ type: 'thinking', thinking: '' }, { type: 'text', text: JSON.generate(out) }])
  when :overload_then_ok
    if $hits == 1 then res.status = 529; res['retry-after'] = '0'; res.body = '{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}'
    else res.body = JSON.generate(model: 'claude-haiku-5-5', stop_reason: 'end_turn', usage: usage, content: [{ type: 'text', text: '{"verdict":"allow","reason":"fine"}' }]) end
  when :bad then res.status = 400; res.body = '{"type":"error","error":{"type":"invalid_request_error","message":"bad thing"}}'
  when :refusal then res.body = JSON.generate(model: 'claude-sonnet-5-5', stop_reason: 'refusal', stop_details: { type: 'refusal', category: 'cyber' }, usage: usage, content: [])
  when :slow then sleep 4; res.body = '{}'
  end
end
Thread.new { srv.start }; sleep 0.5
def t(name) ; $hits = 0; $seen = []; print "#{name}: "; r = yield; puts "PASS #{r}"; rescue => e; puts "FAIL #{e.class}: #{e.message}"; end
def check(c, m) raise m unless c end

t('engine picks api') { check(ENGINE == 'api', ENGINE); ENGINE }
t('picks ok + request shape') {
  $mode = :ok
  out, ms, usd = run_claude('hello', PICKS_SCHEMA)
  h, b = $seen[0]
  check(h['x-api-key'] == ['test-key'] && h['anthropic-version'] == ['2023-06-01'], 'headers')
  check(h['anthropic-beta'] == ['server-side-fallback-2026-07-01'] && b['fallbacks'] == 'default', 'fallback')
  check(b['model'] == 'claude-sonnet-5-5' && b['output_config']['effort'] == 'medium', 'model/effort')
  sch = b['output_config']['format']
  check(sch['type'] == 'json_schema', 'fmt')
  check(sch['schema']['additionalProperties'] == false && sch['schema']['properties']['picks']['items']['additionalProperties'] == false, 'addlProps')
  check(!JSON.generate(sch).include?('maxItems') && !JSON.generate(sch).include?('maximum'), 'limits stripped')
  check(b['system'][0]['cache_control'] == { 'type' => 'ephemeral' }, 'cache')
  check(out['picks'].size == 5 && out['picks'].all? { |p| p['match'] == 100 }, 'enforce')
  check((usd - (1000 * 2.0 + 200 * 10.0) / 1e6).abs < 1e-9, "usd #{usd}")
  "5 picks, match clamped, $#{usd}"
}
t('haiku retry on 529, no fallback, low effort') {
  $mode = :overload_then_ok
  out, = run_claude('x', SCREEN_SCHEMA, model: 'haiku', timeout: 25)
  b = $seen[0][1]
  check($hits == 2 && out['verdict'] == 'allow', "hits #{$hits}")
  check(!b.key?('fallbacks') && Array($seen[0][0]['anthropic-beta']).empty? && b['output_config']['effort'] == 'low', 'haiku req')
  "2 attempts"
}
t('400 raises with message') { $mode = :bad; (begin; run_claude('x', SCREEN_SCHEMA); raise 'no error'; rescue RuntimeError => e; check(e.message.include?('bad thing') && e.message.include?('req_test'), e.message); check($hits == 1, 'no retry on 400'); e.message; end) }
t('refusal raises') { $mode = :refusal; (begin; run_claude('x', SCOUT_SCHEMA); raise 'no error'; rescue RuntimeError => e; check(e.message.include?('cyber'), e.message); e.message; end) }
t('timeout respected') { $mode = :slow; s = Time.now; (begin; run_claude('x', SCREEN_SCHEMA, timeout: 3); raise 'no error'; rescue RuntimeError => e; check(Time.now - s < 4.5 && e.message.include?('longer'), "#{Time.now - s}s #{e.message}"); "#{(Time.now - s).round(1)}s"; end) }
t('scout schema converts') { s = api_schema(JSON.parse(SCOUT_SCHEMA)); check(s['properties']['actions']['items']['additionalProperties'] == false, 'x'); 'ok' }

# Scout's "do it for me" actions: only on things the user was shown; nothing on screen while driving
eval(SRC[/^SCOUT_VIEWS = .*$/]); eval(SRC[/^def scout_actions.*?^end\n/m])
t('scout actions allowed only on what the user was shown') {
  ctx = { 'events' => [{ 'id' => 'e1' }], 'flares' => [{ 'id' => 'p3' }], 'me' => { 'friend_handles' => ['nitro_nate'] } }
  raw = [{ 'type' => 'rsvp', 'target' => 'e1' }, { 'type' => 'rsvp', 'target' => 'e999' },
         { 'type' => 'chat', 'target' => 'nitro_nate', 'label' => 'down?' }, { 'type' => 'chat', 'target' => 'stranger' },
         { 'type' => 'directions', 'target' => 'p3' }, { 'type' => 'directions', 'target' => 'n1' }, { 'type' => 'directions', 'target' => 'nope' },
         { 'type' => 'food', 'target' => 'tacos' }, { 'type' => 'food', 'target' => 'sushi_bar' },
         { 'type' => 'flare', 'target' => 'Anyone down for pool at 9?' }, { 'type' => 'flare', 'target' => 'x' },
         { 'type' => 'search', 'target' => 'trivia' }, { 'type' => 'go', 'target' => 'party' }, { 'type' => 'launch_rockets', 'target' => 'e1' }, 'junk']
  got = scout_actions(raw, driving: false, targets: [], places: [{ id: 'n1' }], ctx: ctx, food_ids: %w[tacos bbq sixth])
  want = [%w[rsvp e1], %w[chat nitro_nate], %w[directions p3], %w[directions n1], %w[food tacos], ['flare', 'Anyone down for pool at 9?'], %w[search trivia]]
  check(got.map { |a| [a['type'], a['target']] } == want, got.inspect)
  check(got.find { |a| a['type'] == 'chat' }['label'] == 'down?', 'chat draft kept')
  drv = scout_actions(raw, driving: true, targets: [], places: [{ id: 'n1' }], ctx: ctx, food_ids: %w[tacos])
  check(drv.map { |a| a['type'] }.uniq == ['directions'], "driving: #{drv.inspect}")
  "#{got.size} of #{raw.size} kept; driving keeps directions only"
}
srv.shutdown
