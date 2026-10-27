# Bars: do they serve food, and when does the kitchen close? Three real sources, best first:
#   people who've been there (d['barfood'][id][handle] = {f: 'yes'|'no', c: 'HH:MM' or nil, at}),
#   the bar's own menu (menus.rb asks for a KITCHEN line, and a menu with food sections means food),
#   OpenStreetMap (food=yes, a cuisine on a bar).
# Nothing is guessed: with no source, food is nil and the app asks people who know.
BAR_KINDS = ['bar', 'pub', 'club', 'beer garden'].freeze
BARFOOD_DAYS = 120   # answers older than this stop counting (kitchens change)

def barfood_info(d, p, now = Places.now_mow)
  return {} unless BAR_KINDS.include?(p['kind'])
  menu = MenuIndex.bar(p['id'])
  votes = (d.dig('barfood', p['id']) || {}).values.select { |v| v['at'].to_i > now_ms - BARFOOD_DAYS * 86_400_000 }
  yes, no = votes.count { |v| v['f'] == 'yes' }, votes.count { |v| v['f'] == 'no' }
  food = if yes + no > 0 && yes != no then yes > no
         elsif menu&.dig(:food) || p['food'] == 'yes' || Array(p['cuisine']).any? then true
         elsif p['food'] == 'no' then false
         end
  out = { food: food, food_from: yes + no > 0 && yes != no ? 'people' : menu&.dig(:food) ? 'menu' : food.nil? ? nil : 'map', food_votes: yes + no }
  return out.compact unless food
  if (w = menu&.dig(:kitchen) || Hours.parse(p['kitchen'].to_s))   # the menu (or the map) says when: the real hours, today
    st = Hours.status(w, now)
    out[:kitchen] = st[:always] ? 'always' : st[:state] == 'open' ? 'open' : 'closed'
    out[:kitchen_at] = st[:state] == 'open' ? (st[:always] ? nil : Hours.clock(st[:until])) : st[:opens] && Hours.clock(st[:opens])   # open: till; closed: opens
    out[:kitchen_from] = menu&.dig(:kitchen) ? 'menu' : 'map'
  elsif (c = votes.select { |v| v['f'] == 'yes' && v['c'].to_s =~ /\A\d\d:\d\d\z/ }.max_by { |v| v['at'].to_i })
    h, m = c['c'].split(':').map(&:to_i)
    out[:kitchen] = 'around'   # someone said it closes about then
    out[:kitchen_at] = Hours.clock(h * 60 + m)
    out[:kitchen_from] = 'people'
  end
  out.compact
end

def mount_barfood(server)
  # "Know this bar?": serves food yes/no, and when the kitchen closes (one answer per person, the latest counts)
  route(server, '/api/place/barfood') do |b, h|
    limit!("barfood:#{h}", 60, 3600)
    id = b['id'].to_s[0, 30]
    p = Places.find(id) or raise 'No such place.'
    raise 'Only for bars.' unless BAR_KINDS.include?(p['kind'])
    f = %w[yes no].include?(b['food']) ? b['food'] : raise('Say whether it serves food.')
    c = b['close'].to_s[/\A([01]\d|2[0-3]):[0-5]\d\z/] if f == 'yes'
    store do |d|
      ((d['barfood'] ||= {})[id] ||= {})[h] = { 'f' => f, 'c' => c, 'at' => now_ms }.compact
      { ok: true, place: Places.row(p).merge(barfood_info(d, p)) }
    end
  end
end
