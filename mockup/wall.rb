# Public posts, Instagram/Facebook-style: a photo and/or text, an optional place (from "Add location"), for everyone
# or friends only. They stay (unlike 24-hour stories), get likes and comments, and show in the Posts feed and on
# profiles. d['wall'] holds them, newest last; photos in data/wall. A post can be boosted with coins (rewards.rb) to
# rank first near it for 6 hours.
WALL_DIR = File.join(__dir__, 'data', 'wall')
WALL_MAX = 5000

def wall_visible?(d, p, h, hidden, friends)
  return false if p['removed'] || hidden.include?(p['u']) || d['users'][p['u']]&.dig('banned')
  p['vis'] != 'friends' || p['u'] == h || friends.include?(p['u'])
end

def wall_out(p, h, hidden)
  likes = (p['likes'] || []).reject { |x| hidden.include?(x) }
  p.reject { |k, _| %w[likes removed].include?(k) }.merge(
    'likes' => likes.size, 'liked' => likes.include?(h),
    'comments' => (p['comments'] || []).reject { |c| c['removed'] || hidden.include?(c['u']) }.last(50),
    'boosted' => p['boost'].to_i > now_ms || nil).compact
end

def mount_wall(server)
  # The feed. scope: all (everyone's, ranked: friends, close by, liked, fresh, boosted) | friends | near | user (one profile).
  route(server, '/api/wall', get: true, auth: false) do |_b, h, req|
    limit!("wall:#{client_ip(req)}", 600, 3600)
    qy = req.query
    scope = %w[all friends near user].include?(qy['scope']) ? qy['scope'] : 'all'
    lat, lng = qy['lat'].to_f, qy['lng'].to_f
    near = lat.between?(-90, 90) && lng.between?(-180, 180) && !(lat.zero? && lng.zero?) ? [lat.round(2), lng.round(2)] : nil
    store(write: false) do |d|
      hidden = h ? blocked_between(d, h) : Set.new
      friends = h ? friends_of(d, h) : Set.new
      t = now_ms
      list = (d['wall'] || []).select { |p| wall_visible?(d, p, h, hidden, friends) }
      list = list.select { |p| friends.include?(p['u']) || p['u'] == h } if scope == 'friends'
      list = list.select { |p| p['u'] == qy['h'].to_s } if scope == 'user'
      dist = ->(p) { near && p['place'].is_a?(Hash) ? Spots.km(near[0], near[1], p['place']['lat'], p['place']['lng']) : nil }
      list = list.select { |p| (x = dist.(p)) && x < 8 } if scope == 'near'
      ranked = if %w[all near].include?(scope)
                 list.sort_by do |p|
                   age_h = (t - p['at']) / 3_600_000.0
                   km = dist.(p)
                   -(4.0 / (1 + age_h / 6) + (friends.include?(p['u']) ? 2 : 0) + Math.log(1 + (p['likes'] || []).size + (p['comments'] || []).size) +
                     (km ? [0, 2 - km / 3].max : 0) + (p['boost'].to_i > t ? (km.nil? || km < 15 ? 6 : 0) : 0))
                 end
               else
                 list.sort_by { |p| -p['at'] }
               end
      { posts: ranked.first(60).map { |p| wall_out(p, h, hidden) } }
    end
  end

  route(server, '/api/wall/one', get: true, auth: false) do |_b, h, req|
    store(write: false) do |d|
      hidden = h ? blocked_between(d, h) : Set.new
      p = (d['wall'] || []).find { |x| x['id'] == req.query['id'].to_s }
      raise 'That post is gone.' unless p && wall_visible?(d, p, h, hidden, h ? friends_of(d, h) : Set.new)
      { post: wall_out(p, h, hidden) }
    end
  end

  route(server, '/api/wall/post') do |b, h|
    limit!("wallpost:#{h}", 30, 3600)
    text = b['t'].to_s.strip[0, 2200]
    img = b['img'].to_s
    raise 'Photo too large.' if img.size > 700_000
    raw = img.empty? ? nil : (img[%r{\Adata:image/jpeg;base64,([A-Za-z0-9+/=]+)\z}, 1] or raise 'Photos must be JPEG.')
    raise 'Add a photo or write something.' if text.empty? && !raw
    place = spot_ref(b['place'])
    place = nil unless place.is_a?(Hash)
    reviewed = moderate([text, place && place['name']].compact.join(' · '))
    store do |d|
      p = { 'id' => "w#{SecureRandom.hex(6)}", 'u' => h, 't' => text, 'at' => now_ms, 'vis' => b['vis'] == 'friends' ? 'friends' : 'everyone',
            'likes' => [], 'comments' => [] }
      if raw
        FileUtils.mkdir_p(WALL_DIR)
        name = "#{p['id']}.jpg"
        File.binwrite(File.join(WALL_DIR, name), raw.unpack1('m'))
        p['img'] = "/wall-img/#{name}"
      end
      p['place'] = place if place
      p['unreviewed'] = true if !reviewed || raw
      (d['wall'] ||= []) << p
      d['wall'].shift while d['wall'].size > WALL_MAX
      did_something!(d, h, 'post')
      track!('wall_post', h)
      { ok: true, post: wall_out(p, h, Set.new), coins: quest_rec(d, h)['coins'].to_i }
    end
  end

  # like / comment / uncomment / delete (yours) / boost (yours, costs coins)
  route(server, '/api/wall/act') do |b, h|
    limit!("wallact:#{h}", 600, 3600)
    text = b['t'].to_s.strip[0, 600]
    flagged = b['do'] == 'comment' && !text.empty? && !moderate(text)
    store do |d|
      hidden = blocked_between(d, h)
      p = (d['wall'] || []).find { |x| x['id'] == b['id'].to_s } or raise 'That post is gone.'
      raise 'That post is gone.' unless wall_visible?(d, p, h, hidden, friends_of(d, h))
      case b['do']
      when 'like'
        l = (p['likes'] ||= [])
        l.include?(h) ? l.delete(h) : (l << h; notify!(d, p['u'], 'like', from: h, ref: p['id'], text: "❤️ @#{h} liked your post"))
      when 'comment'
        raise 'Write a comment first.' if text.empty?
        (p['comments'] ||= []) << { 'id' => "k#{SecureRandom.hex(4)}", 'u' => h, 't' => text, 'at' => now_ms, 'unreviewed' => flagged || nil }.compact
        p['comments'].shift while p['comments'].size > 300
        ([p['u']] + p['comments'].map { |c| c['u'] }).uniq.first(20).each do |x|
          notify!(d, x, 'like', from: h, ref: p['id'], text: "💬 @#{h} commented: #{text[0, 70]}")
        end
      when 'uncomment'
        c = (p['comments'] || []).find { |x| x['id'] == b['cid'].to_s } or raise 'That comment is gone.'
        raise Forbidden, 'Only the writer or the post’s owner can remove this.' unless c['u'] == h || p['u'] == h
        c['removed'] = true
      when 'delete'
        raise Forbidden, 'You can only delete your own posts.' unless p['u'] == h
        File.delete(File.join(WALL_DIR, File.basename(p['img']))) rescue nil if p['img']
        p.keep_if { |k, _| %w[id u at].include?(k) }['removed'] = true
        next { ok: true, deleted: true }
      when 'boost'
        raise Forbidden, 'You can only boost your own posts.' unless p['u'] == h
        raise 'Already boosted.' if p['boost'].to_i > now_ms
        q = quest_rec(d, h)
        raise "Boosting costs #{BOOST_COST} 🪙 (you have #{q['coins'].to_i})." if q['coins'].to_i < BOOST_COST
        q['coins'] -= BOOST_COST
        p['boost'] = now_ms + BOOST_MS
      else raise 'bad action'
      end
      { ok: true, post: wall_out(p, h, hidden), coins: quest_rec(d, h)['coins'].to_i }
    end
  end

  # Post photos: random-looking ids; a removed or friends-only post's photo isn't served to people who can't see it.
  server.mount_proc('/wall-img') do |req, res|
    name = req.path[%r{\A/wall-img/(w[0-9a-f]{12}\.jpg)\z}, 1]
    file = name && File.join(WALL_DIR, name)
    next res.status = 404 unless file && File.file?(file)
    viewer = session_user(req)
    ok = store(write: false) do |d|
      p = (d['wall'] || []).find { |x| x['img'] == "/wall-img/#{name}" }
      p && wall_visible?(d, p, viewer, viewer ? blocked_between(d, viewer) : Set.new, viewer ? friends_of(d, viewer) : Set.new)
    end
    next res.status = 404 unless ok
    res['Content-Type'] = 'image/jpeg'
    res['Cache-Control'] = 'private, max-age=86400'
    res.body = File.binread(file)
  end
end
