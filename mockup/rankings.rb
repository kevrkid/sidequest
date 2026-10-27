# 🏆 Best of Austin: rankings by category (pizza, sushi, cocktail menus, live music, DJ nights, sports bars…).
# fetch_rankings.rb does the research (Claude reads the web: local best-of lists, awards, Reddit, videos; every link
# checked) into data/rankings.json; this file scores it live and serves it. A spot's score (0-100) is:
#   web       how many independent sources name it, weighted by kind (an award or an editor's list counts more than a
#             Reddit thread or a video), how recent, and how high on the list
#   community what Side Quest people say: ⭐ ratings (pulled toward the middle until enough people rate), "would go
#             back", favorites and check-ins; its weight grows with the number of ratings (up to 40%)
#   data      what we know ourselves: a long drink menu for the drink categories, a happy hour
# Every number shown comes with its reasons; nothing is made up (places, quotes and links come from the research).
# Needs from server.rb: route, store, limit!, Places, PUBLIC_FILES; MenuIndex (menu_finds.rb) when there.

require 'set'
RANK_FILE = ENV['SQ_RANKINGS_FILE'] || File.join(__dir__, 'data', 'rankings.json')
RANK_VOTE_HOURLY = 60

# key => [group, emoji, title, what the research looks for, what people want to know]
RANK_GROUPS = [['food', '🍽️', 'Food'], ['drinks', '🍸', 'Drinks'], ['music', '🎶', 'Music & DJs'], ['sports', '🏈', 'Sports'],
               ['hang', '🎯', 'Things to do']].freeze
RANK_CATS = {
  'pizza' => ['food', '🍕', 'Pizza', 'pizza (Neapolitan, New York, Detroit style, pizza trucks)', 'the pie to order and the style'],
  'sushi' => ['food', '🍣', 'Sushi', 'sushi and omakase', 'omakase or à la carte, price, the rolls/nigiri to get'],
  'tacos' => ['food', '🌮', 'Tacos', 'tacos (taquerias and taco trucks; not breakfast tacos)', 'the taco to get'],
  'breakfast_tacos' => ['food', '🥚', 'Breakfast tacos', 'breakfast tacos', 'the taco to get and how early they open'],
  'bbq' => ['food', '🍖', 'BBQ', 'Texas barbecue (brisket, ribs, sausage)', 'the meat to get and how long the line is'],
  'burgers' => ['food', '🍔', 'Burgers', 'burgers', 'the burger to get'],
  'texmex' => ['food', '🧀', 'Tex-Mex', 'Tex-Mex (queso, enchiladas, fajitas)', 'the plate to get'],
  'mexican' => ['food', '🌶️', 'Mexican', 'regional and interior Mexican restaurants (not Tex-Mex)', 'the dish to get'],
  'italian' => ['food', '🍝', 'Italian', 'Italian restaurants and pasta', 'the pasta or dish to get'],
  'indian' => ['food', '🍛', 'Indian', 'Indian and South Asian restaurants', 'the dishes to get'],
  'thai' => ['food', '🍜', 'Thai', 'Thai restaurants', 'the dishes to get'],
  'ramen' => ['food', '🍥', 'Ramen', 'ramen', 'the bowl to get'],
  'vietnamese' => ['food', '🥢', 'Vietnamese', 'Vietnamese (pho, banh mi, bun)', 'the dish to get'],
  'chinese' => ['food', '🥟', 'Chinese', 'Chinese restaurants (dim sum, Sichuan, noodles, dumplings)', 'the dishes to get'],
  'korean' => ['food', '🔥', 'Korean', 'Korean restaurants and Korean BBQ', 'the dishes to get'],
  'mediterranean' => ['food', '🥙', 'Mediterranean', 'Mediterranean and Middle Eastern restaurants', 'the dishes to get'],
  'seafood' => ['food', '🦞', 'Seafood', 'seafood and oyster bars', 'the dishes to get, oyster happy hour'],
  'steak' => ['food', '🥩', 'Steak', 'steakhouses', 'the cut to get and the price'],
  'fried_chicken' => ['food', '🍗', 'Fried chicken', 'fried chicken and hot chicken', 'the plate to get and the heat'],
  'brunch' => ['food', '🥞', 'Brunch', 'brunch', 'the dish to get, bottomless deals, reservations'],
  'food_trucks' => ['food', '🚚', 'Food trucks', 'food trucks and trailer parks (any cuisine)', 'the dish to get and where it parks'],
  'late_night' => ['food', '🌙', 'Late-night eats', 'late-night food (open past midnight)', 'how late it is open and what to get'],
  'vegan' => ['food', '🥗', 'Vegan & vegetarian', 'vegan and vegetarian restaurants', 'the dish to get'],
  'dessert' => ['food', '🍦', 'Dessert', 'dessert, ice cream and bakeries', 'the thing to get'],
  'coffee' => ['food', '☕', 'Coffee', 'coffee shops', 'the drink to get, good for working or not'],
  'cocktails' => ['drinks', '🍸', 'Cocktail bars', 'cocktail bars', 'the cocktail to get'],
  'drink_menus' => ['drinks', '📜', 'Best drink menus', 'bars and restaurants with the most creative or deepest drink menus (cocktail lists, agave, whiskey, zero-proof)', 'what is special about the menu and the drink to get'],
  'margaritas' => ['drinks', '🍹', 'Margaritas', 'margaritas', 'the margarita to get'],
  'agave' => ['drinks', '🌵', 'Mezcal & tequila bars', 'mezcal and tequila / agave bars', 'what to try'],
  'beer' => ['drinks', '🍺', 'Breweries & craft beer', 'breweries, taprooms and craft beer bars', 'the beer to get, dog / kid friendly'],
  'wine' => ['drinks', '🍷', 'Wine bars', 'wine bars', 'what to try, natural wine or not'],
  'happy_hour' => ['drinks', '🍻', 'Happy hours', 'happy hours (deals on drinks and food)', 'the hours and the deals'],
  'rooftops' => ['drinks', '🌆', 'Rooftop bars', 'rooftop bars and bars with a view', 'the view and the drink to get'],
  'patios' => ['drinks', '🌳', 'Patios', 'bars and restaurants with great patios / beer gardens', 'the vibe and whether dogs are welcome'],
  'dive_bars' => ['drinks', '🎱', 'Dive bars', 'dive bars', 'what makes it great (cheap drinks, jukebox, pool)'],
  'live_music' => ['music', '🎸', 'Live music', 'live music venues and bars with live music most nights', 'the kind of music and the best nights'],
  'dj_nights' => ['music', '🎧', 'DJs & dance nights', 'dance clubs and DJ nights: venues with resident DJs and weekly dance parties (house, techno, hip-hop, Latin, disco)', 'which night, the music and who spins'],
  'jazz' => ['music', '🎷', 'Jazz & blues', 'jazz and blues clubs', 'the best nights'],
  'karaoke' => ['music', '🎤', 'Karaoke', 'karaoke bars and nights', 'which nights, private rooms or stage'],
  'latin_dance' => ['music', '💃', 'Latin dance', 'salsa, bachata and Latin dance nights', 'which night, lessons first or not'],
  'lgbtq' => ['music', '🏳️‍🌈', 'LGBTQ+ bars', 'LGBTQ+ bars and clubs', 'the best nights (drag, dance)'],
  'sports_bars' => ['sports', '📺', 'Sports bars', 'sports bars and the best places to watch a game', 'screens, sound on for games, which teams'],
  'soccer' => ['sports', '⚽', 'Soccer pubs', 'pubs and bars to watch soccer (Austin FC, Premier League, World Cup)', 'which club\'s supporters go there, early-morning games'],
  'game_day' => ['sports', '🤘', 'Game day spots', 'places to watch Texas Longhorns football and pregame', 'the vibe on game day'],
  'trivia' => ['hang', '🧠', 'Trivia nights', 'trivia nights at bars', 'which night and how hard'],
  'games' => ['hang', '🕹️', 'Arcade & game bars', 'arcade bars, bowling, pool, darts, shuffleboard and board game bars', 'the games'],
  'comedy' => ['hang', '😂', 'Comedy', 'comedy clubs and open mics', 'which nights and the price']
}.freeze
RANK_DRINKY = %w[cocktails drink_menus margaritas agave beer wine happy_hour rooftops patios dive_bars].freeze

module Rankings
  KIND_W = { 'award' => 1.3, 'list' => 1.0, 'guide' => 0.9, 'review' => 0.8, 'news' => 0.7, 'reddit' => 0.6, 'video' => 0.6, 'social' => 0.5 }.freeze
  @lock = Mutex.new
  @data = nil
  @mt = nil

  module_function

  def data
    @lock.synchronize do
      mt = File.exist?(RANK_FILE) ? File.mtime(RANK_FILE) : nil
      if mt != @mt
        @data = (mt && JSON.parse(File.read(RANK_FILE)) rescue nil) || { 'cats' => {} }
        @mt = mt
      end
      @data
    end
  end

  def recency(y)
    y = y.to_i
    return 0.75 if y.zero?
    age = Time.now.year - y
    age <= 0 ? 1.0 : age == 1 ? 0.9 : age == 2 ? 0.75 : 0.5
  end

  # One source's weight: its kind, how recent, how high on its list (#1 counts a little more than #15)
  def source_w(s)
    r = s['rank'].to_i
    KIND_W.fetch(s['kind'].to_s, 0.6) * recency(s['year']) * (r.positive? ? [1.15 - 0.025 * (r - 1), 0.75].max : 1.0)
  end

  # Same outlet named twice (two Eater lists) counts once and a half, not twice; all the videos together (or all the
  # Reddit threads) count like one outlet, so three TikToks can't outweigh an editor's list
  def web_raw(item)
    by = Array(item['sources']).group_by { |s| %w[video reddit social].include?(s['kind']) ? s['kind'] : s['outlet'].to_s.downcase }
    by.values.sum { |ss| w = ss.map { |s| source_w(s) }.sort.reverse; w[0] + w[1..].sum * 0.5 }
  end

  def outlet_names(item)
    Array(item['sources']).reject { |s| %w[video reddit social].include?(s['kind']) }.map { |s| s['outlet'].to_s }.reject(&:empty?).uniq
  end

  # Ratings from people whose accounts still exist (a deleted account's ratings stop counting at once)
  def votes_for(d, k, id)
    ((d['rank_votes'] || {})[k] || {})[id].to_h.select { |h, _| d['users'][h] && !d['users'][h]['banned'] }
  end

  def community(d, k, item, place_id)
    v = votes_for(d, k, item['id'])
    n = v.size
    stars = v.values.sum { |x| x['s'].to_i }
    back = v.values.count { |x| x['b'] == true }
    said_back = v.values.count { |x| [true, false].include?(x['b']) }
    bayes = (stars + 3.6 * 5) / (n + 5.0)   # 5 make-believe 3.6-star ratings: one 5-star rating doesn't make #1
    saves = place_id ? (d['saves'] || {}).values.sum { |l| l.count { |x| x['k'] == 'place' && x['id'] == place_id } } : 0
    checks = place_id ? (d['quest'] || {}).values.sum { |q| q['checkins'].to_a.count { |c| c['id'] == place_id } } : 0
    back_rate = said_back.positive? ? back.to_f / said_back : nil
    score = (bayes - 1) / 4 * 100 * 0.75 + [100, 25 * Math.log2(1 + saves + checks)].min * 0.25
    score = score * 0.85 + back_rate * 100 * 0.15 if back_rate
    { n: n, avg: n.positive? ? (stars.to_f / n).round(1) : nil, back: back, said_back: said_back, saves: saves, checks: checks, score: score }
  end

  def menu_bits(place_id, k)
    return {} unless place_id && defined?(MenuIndex)
    MenuIndex.load
    files = MenuIndex.instance_variable_get(:@files) || {}
    f = files.find { |path, _| File.basename(path, '.json') == place_id }&.last
    return {} unless f
    drinks = f[1].count { |x| x[1] =~ /cocktail|drink|bar|wine|beer|spirit|agave|tequila|mezcal|whisk|margarita|zero.?proof|mocktail/i }
    happy = f[2]
    { drinks: drinks, happy: happy && happy['week'] ? { label: happy['hours'].to_s[0, 60], now: Hours.status(happy['week'], Places.now_mow)[:state] == 'open' } : nil,
      dishes: f[1].size }
  rescue StandardError
    {}
  end

  def reasons(item, c, mb, k)
    out = []
    ou = outlet_names(item)
    aw = Array(item['sources']).select { |s| s['kind'] == 'award' }.map { |s| s['title'].to_s }.reject(&:empty?)
    out << "🏆 #{aw.first[0, 70]}" if aw.any?
    out << "📰 On #{ou.size} best-of list#{ou.size == 1 ? '' : 's'}: #{ou.first(3).join(', ')}#{ou.size > 3 ? " +#{ou.size - 3}" : ''}" if ou.any?
    vids = Array(item['sources']).count { |s| s['kind'] == 'video' }
    out << "▶️ #{vids} video#{vids == 1 ? '' : 's'}" if vids.positive?
    rd = Array(item['sources']).count { |s| s['kind'] == 'reddit' }
    out << "💬 Locals on Reddit back it" if rd.positive?
    out << "⭐ #{c[:avg]} from #{c[:n]} on Side Quest" if c[:n].positive?
    out << "🔁 #{c[:back]} of #{c[:said_back]} would go back" if c[:said_back] >= 2
    out << "❤️ #{c[:saves]} favorite#{c[:saves] == 1 ? '' : 's'}" if c[:saves] >= 2
    out << "🍸 #{mb[:drinks]} drinks on the menu" if RANK_DRINKY.include?(k) && mb[:drinks].to_i >= 15
    out << "🍻 Happy hour on now" if mb.dig(:happy, :now)
    out
  end

  # The list for one category, best first, for one person (their ratings, places they've been) at one spot
  def list(d, k, h, lat, lng)
    cat = data['cats'][k] or return nil
    items = Array(cat['places'])
    raw = items.map { |it| web_raw(it) }
    top = raw.max.to_f
    been = h ? (((d['quest'] || {})[h] || {})['checkins'].to_a.map { |x| x['id'] }.to_set) : Set.new
    rows = items.each_with_index.map do |it, i|
      p = it['place_id'] && Places.find(it['place_id'])
      web = top.positive? ? 100 * (raw[i] / top)**0.8 : 0
      c = community(d, k, it, p && p['id'])
      mb = menu_bits(p && p['id'], k)
      data_s = [mb[:drinks].to_i * 2.5, 70].min + (mb[:happy] ? 30 : 0)
      wc = [0.4, 0.06 * c[:n]].min
      wd = RANK_DRINKY.include?(k) && mb.any? ? 0.1 : 0
      score = (1 - wc - wd) * web + wc * c[:score] + wd * data_s
      la = p ? p['lat'] : it['lat']
      ln = p ? p['lng'] : it['lng']
      mi = lat && la ? Places.miles(lat, lng, la, ln) : nil
      mine = h && votes_for(d, k, it['id'])[h]
      { id: it['id'], name: it['name'], area: it['area'], addr: (p && p['addr']) || it['address'], score: score.round,
        parts: { web: web.round, people: c[:n].positive? ? c[:score].round : nil }, reasons: reasons(it, c, mb, k),
        known_for: it['known_for'], order: Array(it['order']).first(4), vibe: it['vibe'], price: it['price'], best_time: it['best_time'],
        hype: it['hype'], ig: it['instagram'], web_url: it['website'],
        sources: Array(it['sources']).map { |s| s.slice('outlet', 'title', 'url', 'kind', 'year') },
        place: p ? Places.row(p, Hours.status(p['week'], Places.now_mow), mi) : nil, lat: la, lng: ln, mi: mi && mi.round(1),
        votes: { n: c[:n], avg: c[:avg], back: c[:back], said_back: c[:said_back] },
        mine: mine ? { stars: mine['s'], back: mine['b'] } : nil, been: !!(p && been.include?(p['id'])),
        nights: it['nights'] }.compact
    end
    rows.sort_by! { |r| [-r[:score], r[:name].to_s] }
    rows.each_with_index { |r, i| r[:rank] = i + 1 }
    g = RANK_CATS[k]
    { k: k, group: g[0], e: g[1], title: g[2], want: g[4], at: cat['at'], items: rows, nights: Array(cat['nights']),
      sources: Array(cat['sources']).first(12) }
  end

  def index(d)
    cats = data['cats']
    RANK_GROUPS.map do |gk, ge, gt|
      list = RANK_CATS.select { |_, v| v[0] == gk }.map do |k, v|
        c = cats[k]
        next nil unless c && Array(c['places']).any?
        top = Array(c['places']).max_by { |it| web_raw(it) }
        { k: k, e: v[1], title: v[2], n: c['places'].size, top: top && top['name'], at: c['at'] }
      end.compact
      { k: gk, e: ge, title: gt, cats: list }
    end.reject { |g| g[:cats].empty? }
  end
end

# Scout: "best sushi?", "where should I watch the game?", "a good DJ night Friday" get the list itself. Most specific first.
RANK_WORDS = [
  ['breakfast_tacos', /breakfast tacos?/i], ['drink_menus', /drinks? (menu|list)s?|cocktail (menu|list)s?/i], ['happy_hour', /happy\s*hours?/i],
  ['soccer', /soccer|f[uú]tbol|premier league|austin fc|world cup/i], ['game_day', /longhorns|\but\b (football|game)|game ?day|tailgat/i],
  ['sports_bars', /sports? bars?|watch (the |a )?(game|games|football|nfl|nba|mlb|nhl|ufc|fights?|match)|sports/i],
  ['latin_dance', /salsa|bachata|cumbia|latin (dance|night|club)s?/i], ['lgbtq', /lgbt|gay bars?|queer|drag (show|brunch|night)/i],
  ['karaoke', /karaoke/i], ['jazz', /jazz|blues/i], ['dj_nights', /\bdjs?\b|dance clubs?|dancing|\bclubs?\b|edm|techno|house music|dance part(y|ies)/i],
  ['live_music', /live music|concerts?|\bbands?\b|music venues?|\bgigs?\b/i], ['trivia', /trivia|quiz night/i],
  ['games', /arcade|bowling|\bpool\b|darts|shuffleboard|board games?|skee/i], ['comedy', /comedy|stand[- ]?up|open mic/i],
  ['margaritas', /\bmargs?\b|margaritas?/i], ['agave', /mezcal|tequila|agave/i], ['cocktails', /cocktails?|speakeas/i],
  ['beer', /\bbeers?\b|brewer(y|ies)|taprooms?|\bipas?\b/i], ['wine', /\bwine/i], ['rooftops', /rooftops?|with a view/i],
  ['patios', /patios?|beer gardens?|outdoor seating/i], ['dive_bars', /dive bars?|\bdives?\b/i],
  ['pizza', /pizza|pizzeria|\bslices?\b/i], ['sushi', /sushi|omakase|nigiri/i], ['bbq', /\bbbq\b|barbe?cue|brisket/i],
  ['burgers', /burgers?/i], ['texmex', /tex[- ]?mex|queso|enchiladas?|fajitas?/i], ['tacos', /\btacos?\b|taquer/i],
  ['mexican', /mexican|\bmole\b|birria/i], ['italian', /italian|pasta/i], ['indian', /indian|curry|biryani|tikka/i], ['thai', /\bthai\b/i],
  ['ramen', /ramen/i], ['vietnamese', /vietnamese|\bpho\b|banh mi/i], ['chinese', /chinese|dim sum|dumplings?|sichuan|szechuan/i],
  ['korean', /korean|k-?bbq/i], ['mediterranean', /mediterranean|middle eastern|falafel|shawarma|greek|lebanese/i],
  ['seafood', /seafood|oysters?|crawfish/i], ['steak', /steak/i], ['fried_chicken', /fried chicken|hot chicken|chicken sandwich/i],
  ['brunch', /brunch/i], ['food_trucks', /food trucks?|food trailers?/i], ['late_night', /late[- ]night|after midnight|open late/i],
  ['vegan', /vegan|vegetarian|plant[- ]based/i], ['dessert', /dessert|ice cream|bakery|bakeries|donuts?|\bcakes?\b|cookies?|pastr/i],
  ['coffee', /coffee|espresso|latte|\bcafes?\b/i]
].freeze
RANK_ASK = /\b(best|top|favou?rite|good|great|greatest|recommend|suggest|must[- ]try|go-to|worth|where should|spots? for|places? (for|to)|which)\b/i

def rank_for_scout(d, q, near)
  return nil unless q =~ RANK_ASK
  k = RANK_WORDS.find { |_, re| q =~ re }&.first
  return nil unless k && (Rankings.data['cats'][k] || {})['places'].to_a.any?
  j = Rankings.list(d, k, nil, near&.first, near&.last)
  rows = j[:items].first(10).map do |x|
    { id: x[:place] && x[:place][:id], name: x[:name], rank: x[:rank], score: x[:score], area: x[:area], why: x[:reasons].first(3),
      known_for: x[:known_for], get: x[:order], price: x[:price], best_time: x[:best_time], nights: x[:nights], mi: x[:mi],
      status: x[:place] && x[:place][:status], lat: x[:lat], lng: x[:lng], kind: x[:place] && x[:place][:kind] }.compact
  end
  [rows, "Side Quest's Best of Austin list for #{j[:title].downcase} (rank 1 = best; score from local best-of lists, awards, " \
         "Reddit, videos and Side Quest ratings; why = the reasons). Lead with the top picks, say what to get and why it " \
         "ranks, mention distance or open now when it helps. A place with an id can be lit up with a place action. Tell " \
         "them the full list is under 🏆 Best of in the app. Don't add places that aren't on the list."]
end

def mount_rankings(server)
  # Everyone (guests too) can look; rating and suggesting need an account.
  route(server, '/api/rankings', get: true, auth: false) do |_b, _h|
    store(write: false) { |d| { updated: Rankings.data['updated'], groups: Rankings.index(d) } }
  end

  route(server, '/api/rankings/cat', get: true, auth: false) do |_b, h, req|
    k = req.query['k'].to_s
    raise 'No such list.' unless RANK_CATS.key?(k)
    lat = req.query['lat'].to_s.empty? ? nil : req.query['lat'].to_f
    lng = req.query['lng'].to_s.empty? ? nil : req.query['lng'].to_f
    lat = lng = nil unless lat && lng && lat.between?(29.0, 31.8) && lng.between?(-99.0, -96.5)
    store(write: false) { |d| Rankings.list(d, k, h, lat, lng) } or raise 'That list is still being put together. Check back soon.'
  end

  # ⭐ 1-5 and "would you go back?" (true/false/nil), one per person per spot per list; stars 0 takes yours back
  route(server, '/api/rankings/vote') do |b, h|
    k = b['k'].to_s
    id = b['id'].to_s
    raise 'No such list.' unless RANK_CATS.key?(k)
    raise 'No such spot.' unless Array((Rankings.data['cats'][k] || {})['places']).any? { |x| x['id'] == id }
    s = b['stars'].to_i
    raise 'Pick 1 to 5 stars.' unless s.between?(0, 5)
    limit!("rank:#{h}", RANK_VOTE_HOURLY, 3600)
    store do |d|
      v = (((d['rank_votes'] ||= {})[k] ||= {})[id] ||= {})
      if s.zero? then v.delete(h)
      else v[h] = { 's' => s, 'b' => [true, false].include?(b['back']) ? b['back'] : v.dig(h, 'b'), 'at' => (Time.now.to_f * 1000).to_i }.compact
      end
      it = Rankings.data['cats'][k]['places'].find { |x| x['id'] == id }
      c = Rankings.community(d, k, it, it['place_id'])
      { votes: { n: c[:n], avg: c[:avg], back: c[:back], said_back: c[:said_back] }, mine: v[h] && { stars: v[h]['s'], back: v[h]['b'] } }
    end
  end

  # "You missed one": a spot (or a DJ night) for a list; the next research run looks it up like any other candidate
  route(server, '/api/rankings/suggest') do |b, h|
    k = b['k'].to_s
    raise 'No such list.' unless RANK_CATS.key?(k)
    name = b['name'].to_s.gsub(/\s+/, ' ').strip[0, 80]
    why = b['why'].to_s.gsub(/\s+/, ' ').strip[0, 200]
    raise 'Which spot?' if name.size < 2
    limit!("ranksug:#{h}", 10, 86_400)
    store do |d|
      l = (d['rank_suggest'] ||= [])
      l << { 'k' => k, 'name' => name, 'why' => why, 'h' => h, 'at' => (Time.now.to_f * 1000).to_i }
      l.shift while l.size > 500
      { ok: true }
    end
  end

  # Share pages: /r/<list> shows a preview (title, #1-#3) in chats and opens the app on that list
  server.mount_proc('/r/') do |req, res|
    k = req.path.split('/')[2].to_s
    k = '' unless RANK_CATS.key?(k)
    top = k.empty? ? [] : Rankings.list({ 'users' => {} }, k, nil, nil, nil).to_h[:items].to_a.first(3).map { |x| x[:name] }
    t = k.empty? ? 'Best of Austin · Side Quest' : "Best #{RANK_CATS[k][2].downcase} in Austin · Side Quest"
    desc = top.any? ? top.each_with_index.map { |n, i| "##{i + 1} #{n}" }.join(' · ') : 'The best spots around Austin, ranked from local lists, videos and people who went.'
    e = ->(s) { s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('"', '&quot;') }
    res['Content-Type'] = 'text/html; charset=utf-8'
    res.body = %(<!doctype html><meta charset="utf-8"><title>#{e.(t)}</title><meta property="og:title" content="#{e.(t)}">
<meta property="og:description" content="#{e.(desc)}"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="0;url=/?rank=#{k}"><p><a href="/?rank=#{k}">#{e.(t)}</a></p>)
  end
end
