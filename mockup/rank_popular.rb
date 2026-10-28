# How well known each place and sight is, so a crowded map shows the famous ones first and the rest as you zoom in
# (like Google Maps). Writes data/popular.json: {id => score 0-100}, plus the top of each list for people to read.
#
#   ruby rank_popular.rb          # ~1 minute: Wikipedia page views for every sight / place with an article
#   ruby rank_popular.rb --merge  # rebuild from the cached page views
#
# Signals, all free: Wikipedia readers over the last 60 days (the best "how famous is it" number there is without
# paying for Google ratings), a hand-picked list of Austin institutions, and how complete a place's listing is.
require 'json'
require 'net/http'
require 'uri'
require 'time'
require 'date'

DATA = File.join(__dir__, 'data')
CACHE = File.join(DATA, 'sights_cache')
OUT = File.join(DATA, 'popular.json')
VIEWS = File.join(CACHE, 'pageviews.json')
MERGE = ARGV.include?('--merge')
UA = 'SideQuest/1.0 (sights and local history for an Austin events app; kevrkid@gmail.com)'   # same as fetch_sights.rb: Wikimedia wants a contact

def norm(s) s.to_s.downcase.gsub(/&/, 'and').gsub(/[’']/, '').gsub(/\(.*?\)/, '').gsub(/[^a-z0-9]+/, ' ').sub(/\Athe /, '').strip end

def km(a, b, c, d)
  dy = (a - c) * 110.57; dx = (b - d) * 111.32 * Math.cos(a * Math::PI / 180)
  Math.hypot(dx, dy)
end

# Austin institutions people come for: names as they start in OpenStreetMap (matched on the start of the name).
ICONS = <<~LIST.lines.map { |l| norm(l) }.reject(&:empty?)
  Franklin Barbecue
  Terry Black's
  la Barbecue
  Salt Lick
  Stiles Switch
  Micklethwait
  Valentina's Tex Mex
  Interstellar BBQ
  LeRoy and Lewis
  Iron Works
  Matt's El Rancho
  Juan in a Million
  Veracruz All Natural
  Joe's Bakery
  Fonda San Miguel
  Polvos
  Curra's
  El Chilito
  Licha's Cantina
  Nixta Taqueria
  Suerte
  Discada
  Cisco's
  Pueblo Viejo
  Granny's Tacos
  Taco Joint
  Tacodeli
  Torchy's Tacos
  Kerbey Lane
  Magnolia Cafe
  Bouldin Creek Cafe
  Paperboy
  Bird Bird Biscuit
  Elizabeth Street Cafe
  Perla's
  Clark's Oyster Bar
  Jeffrey's
  Josephine House
  Uchi
  Uchiko
  Odd Duck
  Barley Swine
  Emmer & Rye
  Launderette
  Loro
  Ramen Tatsu-ya
  Kemuri Tatsu-ya
  Dai Due
  Olamaie
  Comedor
  Lenoir
  Justine's
  Hillside Farmacy
  Péché
  Home Slice
  Bufalina
  Via 313
  East Side Pies
  Hopdoddy
  P. Terry's
  Sandy's Hamburgers
  Dirty Martin's
  Top Notch
  Arlo's
  Casino El Camino
  Wu Chow
  Asia Cafe
  Lucky Robot
  Gati
  Amy's Ice Creams
  Lick Honest Ice Creams
  Voodoo Doughnut
  Gourdough's
  Rosen's Bagel
  Sugar Mama's
  Mozart's Coffee
  Jo's Coffee
  Epoch Coffee
  Cosmic Coffee
  Radio Coffee
  Houndstooth Coffee
  Thunderbird Coffee
  Spider House
  Easy Tiger
  Contigo
  Moonshine
  Jack Allen's
  Shady Grove
  Chuy's
  Trudy's
  Austin Java
  Scholz Garten
  Banger's
  Stubb's
  Lustre Pearl
  Container Bar
  Craft Pride
  Midnight Cowboy
  Garage
  Firehouse Lounge
  Roosevelt Room
  Kitty Cohen's
  Whisler's
  Yellow Jacket Social Club
  Shangri-La
  Hotel Vegas
  Rio Rita
  Mohawk
  Barbarella
  Coconut Club
  Oilcan Harry's
  Rain on 4th
  Elysium
  Continental Club
  Broken Spoke
  White Horse
  Sahara Lounge
  Cheer Up Charlies
  Barton Springs Saloon
  Saxon Pub
  Antone's
  Cactus Cafe
  Lazarus Brewing
  Pinthouse
  Meanwhile Brewing
  Zilker Brewing
  Austin Beerworks
  Hops & Grain
  Jester King
  Black Star Co-op
  Workhorse Bar
  Deep Eddy Cabaret
  Ginny's Little Longhorn
  Donn's Depot
  Lala's Little Nugget
  Mean Eyed Cat
  Hole in the Wall
  Posse East
  Cover 3
  Austin Taco Project
  Fareground
  Thicket Food Park
  The Picnic
  Bouldin Acres
  St. Elmo Brewing
  Still Austin
LIST

# Sights everyone visits, whatever their page views say.
SIGHT_ICONS = ['texas state capitol', 'congress avenue bridge', 'barton springs pool', 'zilker park', 'zilker metropolitan park', 'mount bonnell', 'treaty oak',
               'bullock texas state history museum', 'lyndon baines johnson library and museum', 'blanton museum of art', 'texas governor s mansion',
               'moonlight towers', 'driskill hotel', 'paramount theatre', 'french legation', 'elisabet ney museum', 'umlauf sculpture garden',
               'texas state cemetery', 'main building', 'mexic arte museum', 'the contemporary austin', 'laguna gloria', 'hope outdoor gallery',
               'pennybacker bridge', 'stevie ray vaughan statue', 'austin central library', 'mayfield park', 'lady bird lake', 'deep eddy pool',
               'o henry museum', 'harry ransom center', 'thinkery', 'texas memorial museum', 'neill cochran house', 'mckinney falls state park',
               'ladybird johnson wildflower center', 'lady bird johnson wildflower center', 'greetings from austin mural', 'i love you so much mural']

sights = JSON.parse(File.read(File.join(DATA, 'sights.json')))['sights']
places = JSON.parse(File.read(File.join(DATA, 'places.json')))['places']
wiki = Dir[File.join(CACHE, 'wiki_*.json')].flat_map { |f| JSON.parse(File.read(f)) rescue [] }
           .select { |w| w['coordinates'] }.uniq { |w| w['pageid'] }
puts "#{sights.size} sights, #{places.size} places, #{wiki.size} Wikipedia articles with a spot"

# ---- Which Wikipedia article (if any) each sight and place is
title_of = {}
sights.each do |s|
  t = s['url'].to_s[%r{wikipedia\.org/wiki/(.+)\z}, 1] || s['wiki'].to_s[/\Aen:(.+)/, 1]
  title_of[s['id']] = URI.decode_www_form_component(t).tr('_', ' ') if t
end
by_norm = wiki.group_by { |w| norm(w['title']) }
places.each do |p|
  n = norm(p['name']); next if n.size < 5
  w = (by_norm[n] || []).find { |a| c = a['coordinates'][0]; km(p['lat'], p['lng'], c['lat'], c['lon']) < 0.4 }
  w ||= wiki.find { |a| t = norm(a['title']); t.start_with?("#{n} ") && t.size - n.size < 14 && km(p['lat'], p['lng'], a['coordinates'][0]['lat'], a['coordinates'][0]['lon']) < 0.25 }
  title_of[p['id']] = w['title'] if w
end
puts "#{title_of.size} with a Wikipedia article (#{places.count { |p| title_of[p['id']] }} of them places)"

# ---- Page views: 50 articles per request, last 60 days (MediaWiki's PageViewInfo)
views = File.exist?(VIEWS) ? JSON.parse(File.read(VIEWS)) : {}
unless MERGE
  todo = title_of.values.uniq - views.keys
  span = "#{(Date.today << 12).strftime('%Y%m01')}/#{Date.today.strftime('%Y%m01')}"
  todo.each_with_index do |t, i|   # Wikimedia's page view counts: readers (not bots) over the last 12 months
    path = "/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/#{URI.encode_www_form_component(t.tr(' ', '_')).gsub('+', '%20')}/monthly/#{span}"
    res = nil
    4.times do |k|
      res = Net::HTTP.start('wikimedia.org', 443, use_ssl: true, open_timeout: 15, read_timeout: 30) { |h| h.request(Net::HTTP::Get.new(path, 'User-Agent' => UA)) } rescue nil
      break if %w[200 404].include?(res&.code)
      sleep 5 * (k + 1)   # rate limited or dropped: wait and try again
    end
    next warn("  #{t}: #{res&.code || 'no answer'}") unless %w[200 404].include?(res&.code)   # left out: tried again next run
    views[t] = res.code == '200' ? JSON.parse(res.body)['items'].sum { |x| x['views'].to_i } : 0
    (print '.'; File.write(VIEWS, JSON.generate(views))) if (i % 20).zero?; sleep 0.5
  end
  puts
  File.write(VIEWS, JSON.generate(views))
end

# ---- Scores
lv = ->(id) { t = title_of[id]; v = t ? views[t].to_i : 0; [Math.log10(v + 1) - 2, 0].max }   # a year's readers: 1k → 1, 100k → 3
SIGHT_BASE = { 'museum' => 22, 'venue' => 18, 'landmark' => 14, 'nature' => 14, 'view' => 12, 'art' => 8, 'sight' => 6, 'marker' => 2 }.freeze
scores = {}
sights.each do |s|
  sc = SIGHT_BASE[s['kind']] || 5
  sc += 8 if s['photo']
  sc += 3 if s['text']
  sc += 6 if s['rthl']
  sc += 3 if s['nrhp'] || s['listed']
  sc += lv.(s['id']) * 16
  sc += 30 if SIGHT_ICONS.any? { |i| norm(s['name']) == i || norm(s['name']).start_with?("#{i} ") }
  # Wikipedia's map also has news stories, festivals and whole towns: real, but nothing to walk up to
  sc = [sc, 4].min if s['name'] =~ /\A\d{4} |shooting|attack|murders?\b|bombing|massacre|protests?\b|riot|festival\b/i
  sc = [sc, 12].min if s['name'] =~ /, (Williamson County, |Austin, )?Texas\z|\A(Hyde Park|Arboretum|Harris Branch|Woodlawn|Clarksville Historic District) \(Austin/
  scores[s['id']] = [[sc.round, 100].min, 1].max
end
KIND_ADJ = { 'food hall' => 10, 'truck park' => 10, 'beer garden' => 6, 'club' => 6, 'music venue' => 6, 'comedy club' => 6, 'brewery' => 4,
             'theater' => 4, 'cinema' => 2, 'food truck' => 2, 'fast food' => -6 }.freeze
places.each do |p|
  n = norm(p['name'])
  sc = 14 + (KIND_ADJ[p['kind']] || 0)
  sc += 5 if p['web']
  sc += 4 if p['hours']
  sc += 3 if p['menu']
  sc += 2 if p['cuisine']&.any?
  sc += 2 if p['addr']
  sc -= 14 if p['chain'] == 'national'   # every corner has one; they show up close in
  sc += 10 + lv.(p['id']) * 10 if title_of[p['id']]
  sc += 40 if ICONS.any? { |i| n == i || n.start_with?("#{i} ") }
  sc += 6 if p['speakeasy']   # hand-picked from the city's best-of lists
  scores[p['id']] = [[sc.round, 100].min, 1].max
end

top = ->(list, name_key) { list.sort_by { |x| -scores[x['id']] }.uniq { |x| norm(x[name_key]) }.first(40).map { |x| "#{scores[x['id']]}  #{x[name_key]}" } }
File.write(OUT, JSON.generate(built: Time.now.utc.iso8601, scores: scores,
                              top_places: top.(places, 'name'), top_sights: top.(sights, 'name')))
puts "wrote #{OUT}"
puts "\nTop places:", top.(places, 'name').first(25)
puts "\nTop sights:", top.(sights, 'name').first(25)
