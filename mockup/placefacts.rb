# What's at a place, from the people who go there: pool table, darts, DJs, patio, dog friendly, Wi-Fi, when it's busy…
# for bars, restaurants, cafés, venues (Places) and parks / lakes / trails (data/outdoors.json).
#   d['pfacts'][id][handle] = { 'f' => { key => 'y' | 'n' }, 'at' => ms }   one set of answers per person, latest wins
# A fact shows when more people say yes than no (answers from the last year). No free text, so nothing to moderate;
# GET /api/place/facts/index lists the confirmed ones so search can find "pool table" or "dog friendly".
PFACT_KEYS = %w[pool darts dj live karaoke trivia dance patio rooftop tvs games dogs cover happy
                wifi outlets work groups veg resv
                restrooms dogpark swim shade parking courts lit grills
                busy_wkn busy_fsn busy_wkd busy_lunch busy_happy quiet].freeze
PFACT_DAYS = 365
PFACT_IDX = { at: 0, v: nil, lock: Mutex.new }

def outdoor_area(id)
  file = ENV['SQ_OUTDOORS_FILE'] ? File.join(ROOT, ENV['SQ_OUTDOORS_FILE']) : File.join(ROOT, 'data', 'outdoors.json')
  @od_cache = nil if @od_cache && @od_cache[:mtime] != (File.mtime(file) rescue nil)
  @od_cache ||= { mtime: (File.mtime(file) rescue nil),
                  by: ((JSON.parse(File.read(file))['areas'] rescue []) || []).each_with_object({}) { |a, o| o[a['id']] = a if a['name'] } }
  @od_cache[:by][id]
end

def pfact_place!(id)
  id = id.to_s[0, 30]
  return [id, 'place'] if Places.find(id)
  return [id, 'park'] if outdoor_area(id)
  raise 'No such place.'
end

def pfact_summary(d, id, h = nil)
  cut = now_ms - PFACT_DAYS * 86_400_000
  votes = (d.dig('pfacts', id) || {}).select { |_who, v| v['at'].to_i > cut }
  counts = Hash.new { |x, k| x[k] = [0, 0] }
  votes.each_value { |v| (v['f'] || {}).each { |k, a| counts[k][a == 'y' ? 0 : 1] += 1 } }
  { id: id, facts: counts.select { |_k, (y, n)| y > n }.to_h, no: counts.select { |_k, (y, n)| n >= y && n > 0 }.keys,
    people: votes.size, mine: h && votes.dig(h, 'f') || {} }
end

# Confirmed facts across every place: { key => [ids] }, rebuilt at most once a minute (search, the pool / games lists)
def pfact_index
  PFACT_IDX[:lock].synchronize do
    if Time.now.to_f - PFACT_IDX[:at] > 60
      PFACT_IDX[:v] = store(write: false) do |d|
        (d['pfacts'] || {}).keys.each_with_object({}) do |id, o|
          pfact_summary(d, id)[:facts].each_key { |k| (o[k] ||= []) << id }
        end
      end
      PFACT_IDX[:at] = Time.now.to_f
    end
    PFACT_IDX[:v]
  end
end

def mount_placefacts(server)
  route(server, '/api/place/facts', auth: false, get: true) do |_b, h, req|
    id, = pfact_place!(req.query['id'])
    store(write: false) { |d| pfact_summary(d, id, h) }
  end

  # Your answers for one place: { key => 'y' | 'n' | '' } ('' takes your answer back)
  route(server, '/api/place/facts/set') do |b, h|
    limit!("pfacts:#{h}", 60, 3600)
    id, = pfact_place!(b['id'])
    f = b['facts'].is_a?(Hash) ? b['facts'] : raise('Nothing to save.')
    f = f.select { |k, v| PFACT_KEYS.include?(k.to_s) && ['y', 'n', ''].include?(v.to_s) }
    raise 'Nothing to save.' if f.empty?
    store do |d|
      mine = (((d['pfacts'] ||= {})[id] ||= {})[h] ||= { 'f' => {} })
      f.each { |k, v| v.to_s == '' ? mine['f'].delete(k.to_s) : mine['f'][k.to_s] = v.to_s }
      mine['at'] = now_ms
      d['pfacts'][id].delete(h) if mine['f'].empty?
      d['pfacts'].delete(id) if d['pfacts'][id].empty?
      PFACT_IDX[:at] = 0
      pfact_summary(d, id, h)
    end
  end

  # Confirmed facts across every place, for search: { key => [ids] } (rebuilt at most once a minute)
  route(server, '/api/place/facts/index', auth: false, get: true) do |_b, _h, _req, res|
    res['Cache-Control'] = 'public, max-age=60'
    { facts: pfact_index }
  end
end
