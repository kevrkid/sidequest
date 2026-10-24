# Stories, the Instagram parts: who viewed yours (st['views'] = { h => ms }, only you see the list), a poll sticker
# viewers vote on (st['poll'] = { 'q', 'opts' => [a, b], 'votes' => { h => 0|1 } }), and a close-friends list
# (d['users'][h]['close']) for stories only they see (vis 'close'). Text, emoji, place and time stickers are drawn
# into the photo on the phone, so they need nothing here.
STORY_VIEWS_MAX = 3000

def story_poll_clean(p)
  return nil unless p.is_a?(Hash)
  q = p['q'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 80]
  opts = Array(p['opts']).map { |o| o.to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 24] }.reject(&:empty?).first(2)
  return nil if q.empty? || opts.size < 2
  { 'q' => q, 'opts' => opts, 'votes' => {} }
end

# The poll as a phone sees it: counts and your vote; who voted only for the story's author (in /api/story/viewers).
def story_poll_out(poll, h)
  return nil unless poll
  v = poll['votes'] || {}
  { 'q' => poll['q'], 'opts' => poll['opts'], 'n' => [v.values.count(0), v.values.count(1)], 'mine' => v[h] }.compact
end

def close_of(d, h) Array(d['users'][h]&.dig('close')) end

def mount_stories_plus(server)
  # Stories you've watched (sent in small batches). Your own aren't counted.
  route(server, '/api/story/seen') do |b, h|
    limit!("sseen:#{h}", 600, 3600)
    ids = Array(b['ids']).map(&:to_s).uniq.first(50)
    store do |d|
      hidden = blocked_between(d, h)
      d['stories'].each do |st|
        next unless ids.include?(st['id']) && st['u'] != h && !hidden.include?(st['u'])
        v = (st['views'] ||= {})
        v[h] ||= now_ms
        v.shift while v.size > STORY_VIEWS_MAX
      end
      { ok: true }
    end
  end

  # Your story's viewers, newest first, with who liked it and how each voted.
  route(server, '/api/story/viewers') do |b, h|
    store(write: false) do |d|
      st = d['stories'].find { |x| x['id'] == b['id'].to_s && !x['removed'] } or raise 'That story is gone.'
      raise Forbidden, 'Only you can see who viewed your story.' unless st['u'] == h
      hidden = blocked_between(d, h)
      likes = st['likes'] || []
      votes = st.dig('poll', 'votes') || {}
      who = (st['views'] || {}).reject { |x, _| hidden.include?(x) }.sort_by { |_, at| -at }
      { viewers: who.map { |x, at| { h: x, at: at, liked: likes.include?(x), vote: votes[x] }.compact }, poll: story_poll_out(st['poll'], h) }
    end
  end

  route(server, '/api/story/vote') do |b, h|
    limit!("svote:#{h}", 300, 3600)
    store do |d|
      st = d['stories'].find { |x| x['id'] == b['id'].to_s && !x['removed'] } or raise 'That story is gone.'
      raise 'No poll on this story.' unless st['poll']
      raise Forbidden, 'Not available.' if blocked_between(d, h).include?(st['u'])
      opt = b['opt'].to_i
      raise 'No such choice.' unless [0, 1].include?(opt)
      first = !st['poll']['votes'].key?(h)
      st['poll']['votes'][h] = opt
      notify!(d, st['u'], 'like', from: h, ref: st['id'], text: "📊 @#{h} voted #{st['poll']['opts'][opt]} on your story") if first
      { ok: true, poll: story_poll_out(st['poll'], h) }
    end
  end

  # Your close-friends list (friends only).
  route(server, '/api/close') do |b, h|
    store do |d|
      if b.key?('list')
        fr = friends_of(d, h)
        d['users'][h]['close'] = Array(b['list']).map(&:to_s).uniq.select { |x| fr.include?(x) }.first(200)
      end
      { ok: true, close: close_of(d, h) }
    end
  end
end
