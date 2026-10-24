# "Add location" search (spots.rb) on the test places, sights and parks: nearest first, by name, one entry per
# place, and what a post may carry as its place.  ruby test_spots.rb
ENV['SQ_PLACES_FILE'] = File.join(__dir__, 'test_places.json')
ENV['SQ_SIGHTS_FILE'] = 'test_sights.json'
ENV['SQ_OUTDOORS_FILE'] = 'test_outdoors.json'
ENV['SQ_MARKETS_FILE'] = 'test_none.json'
require 'json'; require 'uri'; require 'net/http'
require_relative 'places'
require_relative 'sights'
require_relative 'areas'
require_relative 'spots'
$pass = $fail = 0
def check(name, ok, extra = '') ok ? $pass += 1 : $fail += 1; puts "#{ok ? 'PASS' : 'FAIL'} #{name}#{ok ? '' : " #{extra}"}" end

near = [30.267, -97.74]   # Sixth Street
r = Spots.search('', near: near)[:results]
names = r.map { |x| x[:name] }
check('nearby: closest first, with distance', r.first && r.first[:km] && r.each_cons(2).count { |a, b| a[:km] > b[:km] + 1.2 }.zero?, names.first(5))
check('nearby: bars, parks and sights in one list', names.include?('Sixth Street Saloon') && names.include?('Test Lake') && names.include?('Test State Capitol'), names)
check('nearby: food & drink ahead of a plaque the same distance away', names.index('Late Owl Club') < names.index('Test Moonlight Tower').to_i ||
      !names.include?('Test Moonlight Tower'), names)
check('nearby: nothing 3 km+ away (the Domain, Round Rock)', !names.include?('Domain Pizza Co') && !names.include?('Main Street Taps'), names)
check('nearby: needs a position', Spots.search('', near: nil)[:results].empty?)

s = Spots.search('saloon', near: near)[:results]
check('by name: one word', s.first && s.first[:name] == 'Sixth Street Saloon' && s.first[:e] == '🍸' && s.first[:kind] == 'Bar', s.first)
s = Spots.search('test lake', near: near)[:results]
check('by name: parks and lakes too', s.first && s.first[:name] == 'Test Lake' && s.first[:kind] == 'Lake', s.first)
s = Spots.search('pizza', near: near)[:results]
check('by name: far away places still found', s.any? { |x| x[:name] == 'Domain Pizza Co' }, s)
check('by name: as you type (word starts)', Spots.search('sunr', near: near)[:results].first&.dig(:name) == 'Sunrise Coffee')
check('by name: nothing for nonsense', Spots.search('zzqx', near: near)[:results].empty?)
check('unnamed trailheads left out', Spots.list.none? { |x| x[1].to_s.empty? })

check('post place: a venue id passes', spot_ref('bb') == 'bb')
v = spot_ref('name' => " Grandma's\nPorch ", 'lat' => '30.2', 'lng' => -97.7, 'kind' => 'Added by you', 'junk' => 'x' * 900)
check('post place: picked place is cleaned', v == { 'name' => "Grandma's Porch", 'lat' => 30.2, 'lng' => -97.7, 'kind' => 'Added by you' }, v)
check('post place: long names cut to 60', spot_ref('name' => 'x' * 200, 'lat' => 1, 'lng' => 1)['name'].size == 60)
check('post place: no name or bad coordinates → none', spot_ref('name' => '', 'lat' => 1, 'lng' => 1).nil? && spot_ref('name' => 'a', 'lat' => 'x', 'lng' => 1).nil? &&
      spot_ref('name' => 'a', 'lat' => 99, 'lng' => 1).nil? && spot_ref(['a']).nil? && spot_ref(nil).nil?)

puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
