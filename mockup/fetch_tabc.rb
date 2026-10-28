# Bars and drinks from Texas Alcoholic Beverage Commission licenses (public record, data.texas.gov): every active
# on-premise license in Travis, Williamson and Hays counties (mixed beverage = full bar, wine & beer, beer, private
# club), geocoded with the US Census geocoder (free, public domain). Writes data/tabc.json; `ruby fetch_places.rb
# --merge` uses it to mark places that serve alcohol and to add licensed bars no other source has.
#
#   ruby fetch_tabc.rb          # a few minutes the first time; addresses already geocoded are kept in data/tabc_geo.json
#
# Stdlib only, like the app.
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'fileutils'
require 'securerandom'
$stdout.sync = true

DIR = File.join(__dir__, 'data')
OUT = File.join(DIR, 'tabc.json')
GEO = File.join(DIR, 'tabc_geo.json')   # address → [lat, lng] or [] (no match), so reruns only look up new ones
COUNTIES = %w[Travis Williamson Hays].freeze
TYPES = { 'MB' => 'full', 'N' => 'full', 'BG' => 'beer & wine', 'BE' => 'beer' }.freeze   # on-premise licenses

def get_json(url)
  uri = URI(url)
  r = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) { |h| h.get(uri.request_uri, 'User-Agent' => 'SideQuest/1.0 (bars for a local events app)') }
  raise "HTTP #{r.code}" unless r.code == '200'
  JSON.parse(r.body)
end

where = "primary_status='Active' AND county in(#{COUNTIES.map { |c| "'#{c}'" }.join(',')}) AND license_type in(#{TYPES.keys.map { |t| "'#{t}'" }.join(',')})"
url = "https://data.texas.gov/resource/7hf9-qc9f.json?#{URI.encode_www_form('$select' => 'license_id,trade_name,address,city,zip,license_type,county', '$where' => where, '$limit' => 20_000)}"
rows = get_json(url)
puts "#{rows.size} active on-premise licenses"

geo = (JSON.parse(File.read(GEO)) rescue {})
key = ->(r) { "#{r['address']}, #{r['city']}, TX #{r['zip'].to_s[0, 5]}".upcase.squeeze(' ') }
todo = rows.map { |r| [key.(r), r] }.uniq(&:first).reject { |k, _| geo.key?(k) }
puts "#{todo.size} addresses to geocode (#{geo.size} already known)"

# Census batch geocoder: a CSV of up to 10,000 "id,street,city,state,zip" in, "id,input,Match,Exact,matched,lon lat,..." out.
def census_batch(list)
  boundary = "----sq#{SecureRandom.hex(8)}"
  csv = list.each_with_index.map { |(_, r), i| [i, r['address'], r['city'], 'TX', r['zip'].to_s[0, 5]].map { |x| %("#{x.to_s.tr('"', ' ')}") }.join(',') }.join("\n")
  body = +''
  body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"benchmark\"\r\n\r\nPublic_AR_Current\r\n"
  body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"addressFile\"; filename=\"a.csv\"\r\nContent-Type: text/csv\r\n\r\n#{csv}\r\n--#{boundary}--\r\n"
  uri = URI('https://geocoding.geo.census.gov/geocoder/locations/addressbatch')
  r = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 600) do |h|
    h.post(uri.path, body, 'Content-Type' => "multipart/form-data; boundary=#{boundary}", 'User-Agent' => 'SideQuest/1.0')
  end
  raise "Census geocoder: HTTP #{r.code}" unless r.code == '200'
  out = {}
  r.body.force_encoding('UTF-8').each_line do |line|
    f = line.strip.scan(/"([^"]*)"/).flatten
    next unless f.size >= 3
    i = f[0].to_i
    ll = f[2] == 'Match' && f[5].to_s =~ /\A(-?[\d.]+),(-?[\d.]+)\z/ ? [Regexp.last_match(2).to_f.round(6), Regexp.last_match(1).to_f.round(6)] : []
    out[list[i][0]] = ll if list[i]
  end
  out
end

todo.each_slice(2500).with_index do |chunk, i|
  print "  batch #{i + 1}: #{chunk.size} addresses … "
  begin
    got = census_batch(chunk)
    geo.merge!(got)
    File.write(GEO, JSON.generate(geo))
    puts "#{got.count { |_, v| v.any? }} found"
  rescue StandardError => e
    puts "failed (#{e.message[0, 80]}); run again to retry"
  end
end

lic = rows.map do |r|
  ll = geo[key.(r)]
  next unless ll&.any?
  { 'id' => r['license_id'], 'name' => r['trade_name'].to_s.strip, 'type' => r['license_type'], 'alcohol' => TYPES[r['license_type']],
    'addr' => "#{r['address']}, #{r['city']}".split.map(&:capitalize).join(' '), 'lat' => ll[0], 'lng' => ll[1] }
end.compact
FileUtils.mkdir_p(DIR)
File.write(OUT, JSON.generate('fetched' => Time.now.utc.iso8601, 'source' => 'Texas Alcoholic Beverage Commission (data.texas.gov)', 'licenses' => lic))
puts "#{lic.size} of #{rows.size} licenses with a position → #{OUT}"
