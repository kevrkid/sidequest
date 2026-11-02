# Around town: real groups people can join (run clubs, leagues, social clubs, outdoors, games, dance) and what a
# nightclub is like (music, nights, cover, dress code, crowd). Researched from each group's / venue's own page and local
# press; a fact is kept only when the place itself or two independent sources say so, with the sources listed.
#   data/community.json  {checked, groups: [{id, name, kind, e, desc, when, where, address, lat, lng, cost, url, sources}]}
#   data/nightlife.json  {checked, venues: {place_id => {music, nights, cover, dress, crowd, age, url, sources}}}
# Outside groups aren't Side Quest groups: no members, chat or posts here, just how to find them.
COMMUNITY_FILE = ENV['SQ_COMMUNITY_FILE'] || File.join(__dir__, 'data', 'community.json')
NIGHTLIFE_FILE = ENV['SQ_NIGHTLIFE_FILE'] || File.join(__dir__, 'data', 'nightlife.json')
COMMUNITY_CACHE = { lock: Mutex.new }

def community_load(file)
  COMMUNITY_CACHE[:lock].synchronize do
    mt = File.exist?(file) ? File.mtime(file) : nil
    c = COMMUNITY_CACHE[file]
    return c[:data] if c && c[:mt] == mt
    data = (mt && JSON.parse(File.read(file)) rescue nil) || {}
    COMMUNITY_CACHE[file] = { mt: mt, data: data }
    data
  end
end

def nightlife_for(id)
  v = (community_load(NIGHTLIFE_FILE)['venues'] || {})[id.to_s]
  v && !v['closed'] ? v.reject { |k, x| x.nil? || x == '' || x == [] || k == 'name' } : nil
end

def mount_community(server)
  route(server, '/api/community', auth: false, get: true) do |_b, _h, _req, res|
    res['Cache-Control'] = 'public, max-age=3600'
    d = community_load(COMMUNITY_FILE)
    { checked: d['checked'], groups: d['groups'] || [] }
  end
end
