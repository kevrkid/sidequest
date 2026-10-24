# Friends on the map, Snap-Map-style. Off ("ghost mode") until you turn it on; then your friends (all, or only the
# ones you pick) see your face where you are, exact or rounded to ~500 m, for up to 8 hours after your phone last
# sent it. Pausing hides you for a while. Positions live only in memory (never written to disk); the setting lives in
# d['users'][h]['share'] = { 'mode' => off|friends|some, 'list' => [...], 'precise' => bool, 'until' => ms }.
FMAP = { lock: Mutex.new, at: {} }   # h => { 'lat', 'lng', 'at' }
FMAP_TTL = 8 * 3_600_000

def share_of(d, h)
  s = d['users'][h]&.dig('share') || {}
  { 'mode' => %w[friends some].include?(s['mode']) ? s['mode'] : 'off', 'list' => Array(s['list']), 'precise' => !!s['precise'], 'until' => s['until'].to_i }
end

# Does h show on viewer's map right now?
def shares_with?(d, h, viewer)
  s = share_of(d, h)
  return false if s['mode'] == 'off' || s['until'] > now_ms
  return false unless friends_of(d, h).include?(viewer) && !blocked_between(d, h).include?(viewer)
  s['mode'] == 'friends' || s['list'].include?(viewer)
end

def mount_friendmap(server)
  # Your phone says where it is (the app sends it every minute or so while open, and only while you share).
  route(server, '/api/loc') do |b, h|
    limit!("loc:#{h}", 240, 3600)
    lat = Float(b['lat']) rescue nil
    lng = Float(b['lng']) rescue nil
    raise 'bad position' unless lat && lng && lat.between?(-90, 90) && lng.between?(-180, 180)
    s = store(write: false) { |d| share_of(d, h) }
    if s['mode'] == 'off' || s['until'] > now_ms   # ghost mode or paused: forget where they were
      FMAP[:lock].synchronize { FMAP[:at].delete(h) }
      next { ok: true, shared: false }
    end
    unless s['precise']   # ~500 m squares: friends see the neighborhood, not the building
      lat = (lat / 0.005).round * 0.005
      lng = (lng / 0.005).round * 0.005
    end
    FMAP[:lock].synchronize do
      FMAP[:at].delete_if { |_, x| x['at'] < now_ms - FMAP_TTL } if FMAP[:at].size > 2000
      FMAP[:at][h] = { 'lat' => lat.round(5), 'lng' => lng.round(5), 'at' => now_ms }
    end
    { ok: true, shared: true }
  end

  route(server, '/api/loc/settings') do |b, h|
    limit!("locset:#{h}", 120, 3600)
    store do |d|
      cur = share_of(d, h)
      cur['mode'] = %w[off friends some].include?(b['mode']) ? b['mode'] : cur['mode'] if b.key?('mode')
      cur['list'] = Array(b['list']).map(&:to_s).uniq.select { |x| friends_of(d, h).include?(x) }.first(200) if b.key?('list')
      cur['precise'] = !!b['precise'] if b.key?('precise')
      if b.key?('pause_h')   # 0 = back on now
        hrs = b['pause_h'].to_f.clamp(0, 24 * 7)
        cur['until'] = hrs.zero? ? 0 : now_ms + (hrs * 3_600_000).to_i
      end
      d['users'][h]['share'] = cur
      FMAP[:lock].synchronize { FMAP[:at].delete(h) } if cur['mode'] == 'off' || cur['until'] > now_ms
      { ok: true, share: cur }
    end
  end

  # Friends who share with you, where they last were; and your own setting.
  route(server, '/api/loc/friends', get: true) do |_b, h|
    store(write: false) do |d|
      at = FMAP[:lock].synchronize { FMAP[:at].dup }
      cut = now_ms - FMAP_TTL
      list = friends_of(d, h).select { |x| at[x] && at[x]['at'] > cut && shares_with?(d, x, h) }.map do |x|
        { h: x, lat: at[x]['lat'], lng: at[x]['lng'], at: at[x]['at'], precise: share_of(d, x)['precise'] }
      end
      { friends: list, me: share_of(d, h) }
    end
  end
end
