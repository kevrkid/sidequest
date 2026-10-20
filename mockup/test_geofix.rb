# Event spots (geofix.rb), popularity scores (popular.rb), farmers markets and Scout's areas, offline: ruby test_geofix.rb
require_relative 'geofix'
require_relative 'areas'
require_relative 'places'
require_relative 'popular'
require_relative 'hours'

$pass = $fail = 0
def t(name)
  yield ? ($pass += 1; puts "PASS #{name}") : ($fail += 1; puts "FAIL #{name}")
rescue => e
  $fail += 1; puts "FAIL #{name}: #{e.class} #{e.message}"
end

asked = []
Geofix.define_singleton_method(:enqueue) { |q| asked << q }   # no network here
Geofix.instance_variable_set(:@cache, {})
city = { 'lat' => 30.2649261, 'lng' => -97.7474086, 'geo_precise' => false }
fix = ->(e) { JSON.parse(Geofix.fix_body(JSON.generate(events: [city.merge(e)])))['events'][0] }

t('a park named in the title moves the event there (pickup game at Lakeline Park)') {
  e = fix.('title' => 'GAME #1: 10v10 Wed pickup game - Lakeline Park - FREE', 'venue' => nil)
  e['geo_fixed'] == 'title' && e['lat'] > 30.45 && e['lng'] < -97.78 && e['geo_precise']
}
t("the scrapers' venue names find our venues (ACL Live → Moody Theater, DKR)") {
  a = fix.('title' => 'Madeon', 'venue' => 'ACL Live at The Moody Theater')
  b = fix.('title' => 'Football', 'venue' => 'DKR-Texas Memorial Stadium')
  a['geo_fixed'] == 'venue' && (a['lat'] - 30.2653).abs < 0.002 && b['geo_fixed'] == 'venue' && (b['lat'] - 30.2837).abs < 0.002
}
t('a chain branch is never guessed from its name ("Kerbey Lane Cafe - Central")') {
  e = fix.('title' => 'Brunch', 'venue' => 'Kerbey Lane Cafe - Central', 'address' => '3704 Kerbey Ln, Austin, TX 78731, USA')
  e['geo_none'] && asked.last.start_with?('3704 Kerbey Ln')
}
t('"My home" / "Details in Description" stay off the map and are never looked up') {
  n = asked.size
  a = fix.('title' => 'Water volleyball', 'venue' => 'My home')
  b = fix.('title' => 'Book club', 'venue' => 'Details in Description')
  a['geo_none'] && b['geo_none'] && asked.size == n
}
t('precise events are left alone') {
  e = JSON.parse(Geofix.fix_body(JSON.generate(events: [{ 'title' => 'Show', 'venue' => 'Lakeline Park', 'lat' => 30.1, 'lng' => -97.1, 'geo_precise' => true }])))['events'][0]
  e['lat'] == 30.1 && !e['geo_fixed'] && !e['geo_none']
}
t('addresses are cleaned up before the geocoder sees them') {
  Geofix.clean_address('701 Tillery Street #Suite C Austin, TX 78702 United States') == '701 Tillery Street, Austin, TX 78702' &&
    Geofix.clean_address('211 W. Fourth, Austin') == '211 W. 4th, Austin'
}
t("the geocoder's answer must match the house number and street") {
  good = { 'address' => { 'house_number' => '211', 'road' => 'West 4th Street' } }
  bad = { 'address' => { 'house_number' => '211', 'road' => 'East 5th Street' } }
  Geofix.plausible?('211 W. 4th, Austin', good) && !Geofix.plausible?('211 W. 4th, Austin', bad)
}
t('popularity scores load (0 when unranked)') {
  s = Popular.scores
  s.is_a?(Hash) && Popular['no-such-id'] == 0 && (s.empty? || s.values.all? { |v| v.between?(1, 100) })
}
t('farmers markets: each has a weekly time and a spot in the Austin area') {
  f = File.join(__dir__, 'data', 'markets.json')
  !File.exist?(f) || JSON.parse(File.read(f))['markets'].all? { |m| Hours.parse(m['hours'])&.any? && Geofix.in_box?(m['lat'], m['lng']) }
}
t('Scout finds the neighborhood or town in a question, the longest name first') {
  Areas.find("can you find a local business you'd recommend in Hyde Park")&.dig('name') == 'Hyde Park' &&
    Areas.find('best coffee in East Cesar Chavez')&.dig('name') == 'East Cesar Chavez' &&
    Areas.find('a good spot on South Congress')&.dig('name') == 'South Congress' &&
    Areas.find('tacos near me').nil? && Areas.find('my friend is going home').nil?
}
t("an area's best-known places: all inside it, local ones ahead of national chains") {
  a = Areas.find('Cedar Park')
  list = Places.best_in(a['lat'], a['lng'], a['r'], limit: 15)
  inside = list.all? { |p| Places.miles(a['lat'], a['lng'], p[:lat], p[:lng]) * 1.609 <= a['r'] }
  first_chain = list.index { |p| p[:chain] == 'national' } || list.size
  list.any? && inside && list.first(first_chain).size >= 3
}
puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
