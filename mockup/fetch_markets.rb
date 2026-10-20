# Farmers markets for the map: the weekly ones around Austin with their day and hours, written to data/markets.json.
# OpenStreetMap only knows a few of them, so this is a short hand-kept list (checked against each market's listing,
# October 2026) placed with OpenStreetMap's geocoder; markets come and go, so rerun and recheck now and then.
#
#   ruby fetch_markets.rb
require 'json'
require_relative 'geofix'

OUT = File.join(__dir__, 'data', 'markets.json')
CHECKED = '2026-10'
# name, hours (OpenStreetMap opening_hours style), where to look it up (an address, or fixed [lat, lng]), website
MARKETS = [
  ["SFC Farmers' Market Downtown", 'Sa 09:00-13:00', [30.26725, -97.74711], 'https://sustainablefoodcenter.org/farmers-markets-support/sfc-farmers-markets/', 'Republic Square, 422 Guadalupe St'],
  ["SFC Farmers' Market Sunset Valley", 'Sa 09:00-13:00', '3200 Jones Rd, Sunset Valley, TX', 'https://sustainablefoodcenter.org/farmers-markets-support/sfc-farmers-markets/', 'Toney Burger Center, 3200 Jones Rd'],
  ['Barton Creek Farmers Market', 'Sa 09:00-13:00', '2901 S Capital of Texas Hwy, Austin, TX', 'https://bartoncreekfarmersmarket.org', 'Barton Creek Square parking lot, 2901 S Capital of Texas Hwy'],
  ["Texas Farmers' Market at Lakeline", 'Sa 09:00-13:00', '11200 Lakeline Mall Dr, Cedar Park, TX', 'https://www.lakelinefarmersmarket.com', 'Lakeline Mall, Cedar Park'],
  ["Texas Farmers' Market at Mueller", 'Su 10:00-14:00', [30.30035, -97.70340], 'https://texasfarmersmarket.org', 'Mueller, 2006 Philomena St'],
  ['Domain Farmers Market', 'Su 12:00-16:00', '3220 Amy Donovan Plaza, Austin, TX', 'https://www.lakelinefarmersmarket.com/about-5-1/domainfarmersmarket', 'The Domain, 3220 Amy Donovan Plaza'],
  ['Bee Cave Farmers Market', 'Su 10:00-14:00', '12700 Hill Country Blvd, Bee Cave, TX', nil, 'Hill Country Galleria, 12700 Hill Country Blvd'],
  ["Hutto Farmers' Market", 'We 15:00-19:00', [30.54621, -97.55989], nil, 'Downtown Hutto']
].freeze

def geocode(q)
  sleep 1.1   # OpenStreetMap's rule: one request a second
  uri = URI("https://nominatim.openstreetmap.org/search?#{URI.encode_www_form(q: q, format: 'json', limit: 3, countrycodes: 'us', addressdetails: 1)}")
  r = Net::HTTP.start(uri.host, 443, use_ssl: true, open_timeout: 5, read_timeout: 10) { |h| h.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (farmers market map)') }
  hit = JSON.parse(r.body).find { |x| Geofix.plausible?(q, x) && Geofix.in_box?(x['lat'], x['lon']) }
  hit && [hit['lat'].to_f.round(5), hit['lon'].to_f.round(5)]
rescue StandardError => e
  warn "  #{q}: #{e.message}"; nil
end

list = MARKETS.map.with_index do |(name, hours, where, web, addr), i|
  ll = where.is_a?(Array) ? where : geocode(where)
  next warn("  skipped #{name}: couldn't place #{where}") unless ll
  puts "  #{name.ljust(36)} #{hours.ljust(16)} #{ll.join(',')}"
  { id: "fm#{i + 1}", name: name, hours: hours, lat: ll[0], lng: ll[1], addr: addr, web: web }.compact
end.compact
File.write(OUT, JSON.pretty_generate(checked: CHECKED, markets: list))
puts "wrote #{list.size} markets to #{OUT}"
