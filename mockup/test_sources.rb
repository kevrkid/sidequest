# Places from other open sources (fetch_places.rb's merge rules): Overture Maps categories, chains, duplicates and
# junk; TABC licenses marking alcohol and adding bars. No network.  ruby test_sources.rb
require 'set'
require_relative 'fetch_places'
$pass = $fail = 0
def check(name, ok, extra = '') ok ? $pass += 1 : $fail += 1; puts "#{ok ? 'PASS' : 'FAIL'} #{name}#{ok ? '' : " #{extra}"}" end

check('Overture categories → our kinds', {
  'mexican_restaurant' => 'restaurant', 'fast_food_restaurant' => 'fast food', 'cocktail_bar' => 'bar', 'gastropub' => 'pub', 'brewery' => 'brewery',
  'winery' => 'brewery', 'dance_club' => 'club', 'food_truck_stand' => 'food truck', 'bubble_tea_shop' => 'cafe', 'donut_shop' => 'bakery',
  'music_venue' => 'music venue', 'comedy_club' => 'comedy club', 'theatre_venue' => 'theater', 'movie_theater' => 'cinema', 'bowling_alley' => 'games'
}.all? { |c, k| overture_kind(c) == k }, %w[mexican_restaurant cocktail_bar music_venue movie_theater].map { |c| overture_kind(c) })
check('...and not places to go', %w[candy_store lottery_vendor bingo_hall choir airport_lounge internet_cafe].none? { |c| overture_kind(c) })
check('cuisine from the category', overture_cuisine('mexican_restaurant') == ['mexican'] && overture_cuisine('taco_restaurant') == %w[mexican tacos] &&
      overture_cuisine('texmex_restaurant') == ['tex-mex'] && overture_cuisine('american_restaurant') == [] && overture_cuisine('cocktail_bar') == [])

osm = { 'n1' => { 'id' => 'n1', 'name' => 'Mohawk', 'kind' => 'bar', 'lat' => 30.2699, 'lng' => -97.7359 },
        'n2' => { 'id' => 'n2', 'name' => "Torchy's Tacos", 'kind' => 'restaurant', 'lat' => 30.25, 'lng' => -97.75 } }
brands = Set['sonic', 'starbucks']
ov = [
  { 'id' => 'a1', 'name' => 'Mohawk Austin', 'cat' => 'music_venue', 'conf' => 0.99, 'lat' => 30.2701, 'lng' => -97.7360, 'web' => 'https://mohawkaustin.com', 'ig' => 'https://instagram.com/mohawkaustin' },
  { 'id' => 'a2', 'name' => 'Small Victory', 'cat' => 'cocktail_bar', 'conf' => 0.95, 'lat' => 30.2668, 'lng' => -97.7445, 'addr' => '108 E 7th St, Austin' },
  { 'id' => 'a3', 'name' => 'Sonic Drive-In', 'cat' => 'fast_food_restaurant', 'conf' => 0.9, 'lat' => 30.3, 'lng' => -97.7 },
  { 'id' => 'a4', 'name' => "Jersey Mike's Subs", 'cat' => 'sandwich_shop', 'conf' => 0.9, 'lat' => 30.31, 'lng' => -97.71 },
  { 'id' => 'a5', 'name' => 'AMC Barton Creek Square 14', 'cat' => 'movie_theater', 'conf' => 0.9, 'lat' => 30.257, 'lng' => -97.807, 'brand' => 'AMC Theatres', 'brand_wd' => 'Q294721' },
  { 'id' => 'a6', 'name' => '208 W 4th Street', 'cat' => 'bar', 'conf' => 0.92, 'lat' => 30.266, 'lng' => -97.745 },
  { 'id' => 'a7', 'name' => 'Austin Acting Studio', 'cat' => 'theatre_venue', 'conf' => 0.8, 'lat' => 30.3, 'lng' => -97.72 },
  { 'id' => 'a8', 'name' => 'Austin Symphony Orchestra', 'cat' => 'music_venue', 'conf' => 0.9, 'lat' => 30.27, 'lng' => -97.74 },
  { 'id' => 'a9', 'name' => 'Long Center for the Performing Arts', 'cat' => 'performing_arts_venue', 'conf' => 0.99, 'lat' => 30.2597, 'lng' => -97.7505 },
  { 'id' => 'b1', 'name' => 'Alamo Drafthouse Cinema Mueller', 'cat' => 'movie_theater', 'conf' => 0.99, 'lat' => 30.29856, 'lng' => -97.70457, 'addr' => '1911 Aldrich St, Austin' },
  { 'id' => 'b2', 'name' => 'Alamo Drafthouse Cinema Mueller', 'cat' => 'movie_theater', 'conf' => 0.9, 'lat' => 30.2018, 'lng' => -97.87315, 'addr' => '1911 Aldrich St, Austin' },
  { 'id' => 'b3', 'name' => 'Cap City Comedy Club', 'cat' => 'comedy_club', 'conf' => 1.0, 'lat' => 30.40269, 'lng' => -97.72577, 'addr' => '11506 Century Oaks Terrace' },
  { 'id' => 'b4', 'name' => 'Cap City Comedy Club', 'cat' => 'comedy_club', 'conf' => 0.9, 'lat' => 30.2905, 'lng' => -97.6984, 'addr' => '3801 Berkman Dr' },
  { 'id' => 'b5', 'name' => "Torchy's Tacos", 'cat' => 'taco_restaurant', 'conf' => 0.9, 'lat' => 30.30, 'lng' => -97.70 },
  { 'id' => 'b6', 'name' => 'Candy Jar', 'cat' => 'candy_store', 'conf' => 0.9, 'lat' => 30.3, 'lng' => -97.7 }
]
places = osm.transform_values(&:dup)
st = merge_overture!(places, ov, brands)
names = places.values.map { |p| p['name'] }
check('a place we have: matched, blanks filled (website, Instagram), not added twice',
      names.count { |n| n =~ /Mohawk/ } == 1 && places['n1']['web'] == 'https://mohawkaustin.com' && places['n1']['ig'], places['n1'])
sv = places.values.find { |p| p['name'] == 'Small Victory' }
check('a new bar is added (o… id, kind, address, source)', sv && sv['id'] =~ /\Ao[0-9a-f]{11}\z/ && sv['kind'] == 'bar' && sv['src'] == 'overture' && sv['addr'], sv)
check('national chains left out, by brand or by name with no brand tag', !names.include?('Sonic Drive-In') && !names.include?("Jersey Mike's Subs"))
check('Austin chains stay (another Torchy\'s location)', names.count("Torchy's Tacos") == 2)
check('cinemas stay even when they are chains', places.values.any? { |p| p['name'] =~ /AMC Barton/ && p['chain'] == 'national' && p['kind'] == 'cinema' })
check('an address is not a name', !names.include?('208 W 4th Street'))
check('acting studios and orchestras are not venues; a performing arts center is',
      !names.include?('Austin Acting Studio') && !names.include?('Austin Symphony Orchestra') && names.include?('Long Center for the Performing Arts'))
check('same name at the same address = one place, wherever its pin is', names.count('Alamo Drafthouse Cinema Mueller') == 1)
check('same name, two real addresses: both kept', names.count('Cap City Comedy Club') == 2)
check('candy stores are not places to go', !names.include?('Candy Jar') && st['not a place to go'] == 1, st)

lic = [
  { 'id' => 'L1', 'name' => 'MOHAWK', 'type' => 'MB', 'alcohol' => 'full', 'lat' => 30.2700, 'lng' => -97.7358, 'addr' => '912 Red River St, Austin' },
  { 'id' => 'L2', 'name' => 'COYOTE UGLY SALOON', 'type' => 'MB', 'alcohol' => 'full', 'lat' => 30.2672, 'lng' => -97.7395, 'addr' => '501 E 6th St, Austin' },
  { 'id' => 'L3', 'name' => "MARIACHIS MEXICAN RESTAURANT & BAR", 'type' => 'BG', 'alcohol' => 'beer & wine', 'lat' => 30.35, 'lng' => -97.70, 'addr' => '1 Main St, Austin' },
  { 'id' => 'L4', 'name' => 'CABANA BEVERAGES INC.', 'type' => 'MB', 'alcohol' => 'full', 'lat' => 30.27, 'lng' => -97.75, 'addr' => '2 Main St, Austin' },
  { 'id' => 'L5', 'name' => 'HEADLINERS CLUB', 'type' => 'N', 'alcohol' => 'full', 'lat' => 30.268, 'lng' => -97.742, 'addr' => '221 W 6th St, Austin' },
  { 'id' => 'L6', 'name' => 'SANDY CREEK YACHT CLUB BEER AND WINE LIMITED LIABILITY COMPA', 'type' => 'BG', 'alcohol' => 'beer & wine', 'lat' => 30.4, 'lng' => -97.9, 'addr' => 'x' },
  { 'id' => 'L7', 'name' => 'THE GRAND BILLIARDS', 'type' => 'MB', 'alcohol' => 'full', 'lat' => 30.36, 'lng' => -97.69, 'addr' => '3 Main St, Austin' }
]
tst = merge_tabc!(places, lic, brands)
check('a license marks the place it belongs to (full bar)', places['n1']['alcohol'] == 'full', places['n1'])
cu = places.values.find { |p| p['name'] == 'Coyote Ugly Saloon' }
check('a licensed bar nobody else has is added, with a readable name', cu && cu['kind'] == 'bar' && cu['src'] == 'tabc' && cu['alcohol'] == 'full' && cu['id'] =~ /\At[0-9a-f]{11}\z/, cu)
mr = places.values.find { |p| p['name'] =~ /Mariachis/ }
check('a "Restaurant & Bar" is a restaurant that serves drinks', mr && mr['kind'] == 'restaurant' && mr['alcohol'] == 'beer & wine', mr)
check('billiards is games', places.values.any? { |p| p['name'] == 'The Grand Billiards' && p['kind'] == 'games' })
check('company names, private clubs and cut-off names are not added',
      !places.values.any? { |p| p['name'] =~ /Cabana|Headliners|Yacht/ } && tst['private clubs not added'] == 1, tst)
check('license names read like names', tabc_name("JUANA MARIA'S TEXICAN CAFE #2") == "Juana Maria's Texican Cafe" && tabc_name('BAR ATX, LLC') == 'Bar ATX')

puts "\n#{$pass} passed, #{$fail} failed"
exit($fail.zero? ? 0 : 1)
