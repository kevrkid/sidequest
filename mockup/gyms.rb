# Gyms and fitness (data/gyms.json from fetch_gyms.rb): the map's 🏋️ Gyms layer and chip, check-ins, search.
# Loaded once and again when the file changes; weekly hours worked out like a place's (Hours.parse).
module Gyms
  FILE = ENV['SQ_GYMS_FILE'] ? File.join(__dir__, ENV['SQ_GYMS_FILE']) : File.join(__dir__, 'data', 'gyms.json')
  @lock = Mutex.new
  @data = { at: nil, list: [], by_id: {}, fetched: nil }

  module_function

  def data
    @lock.synchronize do
      mt = (File.mtime(FILE) rescue nil)
      return @data if mt == @data[:at]
      raw = (JSON.parse(File.read(FILE)) rescue {})
      list = (raw['gyms'] || []).map { |g| g.merge('week' => Hours.parse(g['hours'])) }
      @data = { at: mt, list: list, by_id: list.to_h { |g| [g['id'], g] }, fetched: raw['fetched'] }
    end
  end

  def list() data[:list] end
  def find(id) data[:by_id][id.to_s] end
end

def mount_gyms(server)
  route(server, '/api/gyms', auth: false, get: true) do
    d = Gyms.data
    { fetched: d[:fetched], gyms: d[:list] }
  end
end

# Scout: questions about working out get the nearest matching gyms (a kind when the question names one).
GYM_Q = /\b(gyms?|work ?outs?|working out|lift(ing)?|weights|fitness|yoga|pilates|barre|climb(ing)?|boulder(ing)?|crossfit|box(ing)?|kickbox\w*|jiu[- ]?jitsu|bjj|martial arts?|mma|muay thai|karate|spin class|cycling class|dance class(es)?|ice rinks?|ice skat\w*|stick (and|&|n) puck|open skate|rec(reation)? cent(er|re)s?|ymca)\b/i
GYM_Q_KIND = { 'climbing' => /climb|boulder/i, 'yoga' => /yoga|pilates|barre/i, 'boxing' => /box|jiu|bjj|martial|mma|muay|karate/i,
               'crossfit' => /crossfit/i, 'rink' => /rink|skat|hockey|puck/i, 'rec' => /rec(reation)? cent|ymca/i, 'dance' => /danc/i,
               'cycling' => /spin|cycling class/i }.freeze

def scout_gyms(q, near, limit: 8)
  kind = GYM_Q_KIND.find { |_, re| q =~ re }&.first
  lat, lng = near || [30.2672, -97.7431]
  now = Places.now_mow
  Gyms.list.select { |g| !kind || g['kind'] == kind }
       .map { |g| [g, Places.miles(lat, lng, g['lat'], g['lng'])] }.sort_by(&:last).first(limit)
       .map do |g, mi|
         { id: g['id'], name: g['name'], kind: g['kind'], status: Places.label(Hours.status(g['week'], now)), mi: mi.round(1),
           lat: g['lat'], lng: g['lng'], addr: g['addr'], web: g['web'], chain: g['chain'] }.compact
       end
end
