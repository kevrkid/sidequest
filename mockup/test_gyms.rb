# Gyms (gyms.rb): the data file with weekly hours, Scout's nearest-gym lookup by kind.  ruby test_gyms.rb
ENV['SQ_PLACES_FILE'] = File.join(__dir__, 'test_places.json')
ENV['SQ_GYMS_FILE'] = 'test_gyms.json'
require 'json'
require_relative 'hours'
require_relative 'places'
require_relative 'gyms'
$pass = $fail = 0
def check(name, ok, extra = '') ok ? $pass += 1 : $fail += 1; puts "#{ok ? 'PASS' : 'FAIL'} #{name}#{ok ? '' : " #{extra}"}" end

check('loads the file', Gyms.list.size == 4, Gyms.list.size)
check('hours become a week (unknown stays unknown)', Gyms.find('gyn1')['week'].is_a?(Array) && Gyms.find('gyn3')['week'].nil?, Gyms.find('gyn1')['week'])
check('find by id; unknown id is nil', Gyms.find('gyn2')['name'] == 'Test Boulders' && Gyms.find('nope').nil?)

near = [30.27, -97.74]
check('Scout hears gym questions', ['any gyms near me?', 'where can I go climbing', 'yoga tonight', 'stick and puck at an ice rink', 'need a workout'].all? { |q| q =~ GYM_Q })
check('...and not other questions', ['best tacos', 'live music tonight', 'happy hour'].none? { |q| q =~ GYM_Q })
g = scout_gyms('any gyms near me?', near)
check('nearest first, all kinds when none named', g.map { |x| x[:id] } == %w[gyn1 gyn4 gyn2 gyn3], g.map { |x| [x[:id], x[:mi]] })
check('with status, distance and only real details', g.first[:status].is_a?(String) && g.first[:mi] < 0.5 && g.first[:web] && !g.last.key?(:web), g.first)
check('a named kind narrows it: climbing', scout_gyms('where can I go bouldering', near).map { |x| x[:id] } == %w[gyn2])
check('a named kind narrows it: ice rink', scout_gyms('open skate at an ice rink?', near).map { |x| x[:id] } == %w[gyn3])
check('a named kind narrows it: yoga', scout_gyms('hot yoga class', near).map { |x| x[:id] } == %w[gyn4])
check('no position: downtown', scout_gyms('gym', nil).first[:id] == 'gyn1')

puts "\n#{$pass} passed, #{$fail} failed"
exit($fail.zero? ? 0 : 1)
