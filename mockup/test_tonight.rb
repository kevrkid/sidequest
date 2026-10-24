# The 5 PM "tonight for you" picks (v2.rb tonight_push!) on their own, with stand-ins for the server's storage and
# events: who gets one, what's in it, once a day.  ruby test_tonight.rb
require 'json'; require 'time'; require 'date'; require 'securerandom'; require 'openssl'; require 'set'
class RateLimited < StandardError; end
$d = {}
def store(write: true) yield $d end
def now_ms() (Time.now.to_f * 1000).to_i end
def blocked_between(_d, _h) [] end
def track!(*) end
def route(*) end
t = Time.now
$events = [
  { 'uid' => 'aaa', 'title' => 'Comedy Night', 'start' => (t + 3600).strftime('%Y-%m-%dT%H:%M:%S'), 'category' => 'comedy', 'venue' => 'Cap City' },
  { 'uid' => 'bbb', 'title' => 'Jazz Trio', 'start' => (t + 7200).strftime('%Y-%m-%dT%H:%M:%S'), 'category' => 'music', 'venue' => 'Elephant Room' },
  { 'uid' => 'ccc', 'title' => 'Book Club', 'start' => (t + 5400).strftime('%Y-%m-%dT%H:%M:%S'), 'category' => 'community', 'venue' => 'Library' },
  { 'uid' => 'ddd', 'title' => 'Next Week Show', 'start' => (t + 7 * 86_400).strftime('%Y-%m-%dT%H:%M:%S'), 'category' => 'comedy', 'venue' => 'Cap City' }
]
require_relative 'v2'
def events_list() $events end   # after v2.rb, which has its own (the server's events cache)
$pass = $fail = 0
def check(name, ok, extra = '') ok ? $pass += 1 : $fail += 1; puts "#{ok ? 'PASS' : 'FAIL'} #{name}#{ok ? '' : " #{extra}"}" end

$d = { 'users' => { 'amy' => { 'h' => 'amy' }, 'bo' => { 'h' => 'bo' }, 'cy' => { 'h' => 'cy', 'mute' => ['tonight'] }, 'new' => { 'h' => 'new' } },
       'friends' => { 'amy' => ['bo'] }, 'rsvps' => { 'e:bbb' => { 'bo' => 'going' } },
       'taste' => { 'amy' => [{ 'k' => 'event', 'id' => 'e:x', 'cat' => 'comedy', 'venue' => 'Cap City', 'how' => 'going', 'at' => now_ms }],
                    'bo' => [{ 'k' => 'event', 'id' => 'e:y', 'cat' => 'sports', 'how' => 'going', 'at' => now_ms }],
                    'cy' => [{ 'k' => 'event', 'id' => 'e:z', 'cat' => 'comedy', 'how' => 'going', 'at' => now_ms }] } }
tonight_push!(force: true)
amy = ($d['notifs'] || {})['amy'].to_a
check('fits their taste, friends going count, tonight only', amy.size == 1 && amy[0]['t'] == 'tonight' && amy[0]['text'].include?('Comedy Night') &&
      amy[0]['text'] =~ /Jazz Trio \d+:\d\d [AP]M \(1 friend\)/ && !amy[0]['text'].include?('Next Week') && !amy[0]['text'].include?('Book Club'), amy.inspect)
check('nothing that fits: no message', ($d['notifs'] || {})['bo'].to_a.empty?)
check('turned off: no message', ($d['notifs'] || {})['cy'].to_a.empty?)
check('no taste yet: no message', ($d['notifs'] || {})['new'].to_a.empty?)
tonight_push!(force: true)
check('once a day', $d['notifs']['amy'].size == 1)
check('tapping it opens tonight', push_url('tonight', 'tonight') == '/?tonight=1')
puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
