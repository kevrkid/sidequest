# Private messages, Messenger-style: one-to-one chats with friends and named group chats (you + 2-30 friends),
# with replies, emoji reactions, photos, voice notes, shared events / places / stories, unsend, "seen" and
# "typing…". Threads live in d['dms']: "a|b" for two people (as before), "c:<id>" for a group chat, whose name
# and members are in d['chats'][id]. Read marks are d['dm_read'][h][thread] (ms); typing is memory-only.
DM_DIR = File.join(__dir__, 'data', 'dm')
DM_REACTS = %w[❤️ 😂 😮 😢 👍 🔥].freeze
DM_AUDIO = { 'audio/webm' => 'webm', 'audio/mp4' => 'm4a', 'audio/x-m4a' => 'm4a', 'audio/aac' => 'aac', 'audio/mpeg' => 'mp3', 'audio/ogg' => 'ogg' }.freeze
DM_AUDIO_MAX = 3 * 1024 * 1024   # ~3 minutes of phone voice
DM_TYPING = { lock: Mutex.new, at: {} }   # thread => { h => ms }

# The thread a request names: a handle (two people) or "c:<id>" (a group chat). Raises unless h may use it.
def dm_thread!(d, h, with)
  with = with.to_s[0, 40]
  if with.start_with?('c:')
    c = (d['chats'] ||= {})[with[2..]] or raise 'No such chat.'
    raise Forbidden, "You're not in this chat." unless c['members'].include?(h)
    [with, c['members'] - [h], c]
  else
    raise 'No such person.' unless d['users'][with] || with == h
    raise Forbidden, 'Not available.' if blocked_between(d, h).include?(with)
    [dm_key(h, with), [with], nil]
  end
end

def dm_preview(m)
  return 'Unsent a message' if m['gone']
  return "🎤 Voice note#{m['dur'] ? " · #{m['dur']}s" : ''}" if m['aud']
  return "📷 Photo#{m['t'].to_s.empty? ? '' : ": #{m['t']}"}" if m['img']
  return "#{m['card']['e']} #{m['card']['name']}" if m['card'] && m['t'].to_s.empty?
  m['t'].to_s
end

# What a phone gets: no deleted content, ids on old messages (made from their time), reactions as a list.
def dm_out(th)
  th.last(200).map do |m|
    m['id'] ||= "m#{m['at'].to_s(36)}#{m['f'].to_s.sum.to_s(36)}"
    m['gone'] ? m.slice('id', 'f', 'at', 'gone') : m
  end
end

def dm_card(c)
  return nil unless c.is_a?(Hash) && %w[event place story flare group post].include?(c['k'])
  { 'k' => c['k'], 'id' => c['id'].to_s[0, 60], 'name' => c['name'].to_s.gsub(/[[:cntrl:]]/, ' ')[0, 80], 'sub' => c['sub'].to_s.gsub(/[[:cntrl:]]/, ' ')[0, 80],
    'e' => c['e'].to_s[0, 4], 'lat' => (Float(c['lat']) rescue nil), 'lng' => (Float(c['lng']) rescue nil),
    'img' => c['img'].to_s[%r{\A/story-img/s[0-9a-f]{12}\.jpg\z}] }.compact.reject { |_, v| v == '' }
end

def mount_chats(server)
  # Your chats, newest first, with unread counts.
  route(server, '/api/dm/threads', get: true) do |_b, h|
    store(write: false) do |d|
      hidden = blocked_between(d, h)
      read = (d['dm_read'] || {})[h] || {}
      chats = d['chats'] || {}
      list = d['dms'].map do |k, m|
        next if m.empty?
        if k.start_with?('c:')
          c = chats[k[2..]] or next
          next unless c['members'].include?(h)
          with, extra = k, { name: c['name'], members: c['members'], group: true, plan: c['plan'] && c['plan']['status'] }.compact
        else
          next unless k.split('|').include?(h)
          with = (k.split('|') - [h]).first || h
          next if hidden.include?(with)
          extra = {}
        end
        seen = read[k].to_i
        last = m.last
        { with: with, last: { 'f' => last['f'], 't' => dm_preview(last), 'at' => last['at'] },
          unread: m.count { |x| x['f'] != h && x['at'] > seen && !hidden.include?(x['f']) } }.merge(extra)
      end.compact
      # group chats nobody has written in yet still show up
      chats.each_value { |c| list << { with: "c:#{c['id']}", last: { 'f' => c['by'], 't' => 'Chat created', 'at' => c['at'] }, unread: 0, name: c['name'], members: c['members'], group: true } if c['members'].include?(h) && !d['dms']["c:#{c['id']}"]&.any? }
      { threads: list.sort_by { |t| -t[:last]['at'] } }
    end
  end

  # One chat: messages, who has seen up to when, who is typing.
  route(server, '/api/dm', get: true) do |_b, h, req|
    key, others, c = store(write: false) { |d| dm_thread!(d, h, req.query['with']) }
    t = now_ms
    typing = DM_TYPING[:lock].synchronize { (DM_TYPING[:at][key] || {}).select { |x, at| x != h && t - at < 6000 }.keys }
    store(write: false) do |d|
      hidden = blocked_between(d, h)
      th = d['dms'][key] || []
      seen = others.to_h { |x| [x, ((d['dm_read'] || {})[x] || {})[key].to_i] }
      { msgs: dm_out(th).reject { |m| hidden.include?(m['f']) }, seen: seen, typing: typing.reject { |x| hidden.include?(x) },
        chat: c && { id: c['id'], name: c['name'], members: c['members'], by: c['by'], plan: c['plan'] }.compact }.compact
    end
  end

  route(server, '/api/dm/send') do |b, h|
    limit!("dm:#{h}", 240, 3600)
    text = b['text'].to_s.strip[0, 1000]
    card = dm_card(b['card'])
    img = b['img'].to_s
    raise 'Photo too large.' if img.size > 600_000
    raw = img.empty? ? nil : (img[%r{\Adata:image/jpeg;base64,([A-Za-z0-9+/=]+)\z}, 1] or raise 'Photos must be JPEG.')
    aud = b['aud'].to_s[/\Aa[0-9a-f]{16}\.(webm|m4a|aac|mp3|ogg)\z/]
    raise 'Write a message first.' if text.empty? && !card && !raw && !aud
    store do |d|
      key, others, c = dm_thread!(d, h, b['to'])
      raise Forbidden, 'You can message friends. Wave at them on Meet first.' if !c && !friends_of(d, h).include?(others[0])
      if aud
        file = File.join(DM_DIR, aud)
        raise 'That voice note is gone. Record it again.' unless File.file?(file) && MEDIA[:lock].synchronize { MEDIA[:pending][aud]&.dig('h') == h && MEDIA[:pending].delete(aud) }
      end
      th = (d['dms'][key] ||= [])
      msg = { 'id' => "m#{SecureRandom.hex(5)}", 'f' => h, 't' => text, 'at' => now_ms }
      if raw
        FileUtils.mkdir_p(DM_DIR)
        name = "i#{SecureRandom.hex(8)}.jpg"
        File.binwrite(File.join(DM_DIR, name), raw.unpack1('m'))
        msg['img'] = "/dm-img/#{name}"
      end
      if aud
        msg['aud'] = "/dm-aud/#{aud}"
        msg['dur'] = b['dur'].to_i.clamp(1, 600) if b['dur']
      end
      msg['card'] = card if card
      if (re = th.find { |m| m['id'] == b['re'].to_s })   # a reply quotes a bit of the message it answers
        msg['re'] = { 'id' => re['id'], 'f' => re['f'], 't' => re['gone'] ? '' : dm_preview(re)[0, 90] }
      end
      th << msg
      th.shift while th.size > 500
      (d['dm_read'] ||= {})[h] ||= {}
      d['dm_read'][h][key] = msg['at']
      where = c ? " in #{c['name']}" : ''
      others.each { |x| notify!(d, x, 'dm', from: h, ref: c ? key : h, text: "💬 @#{h}#{where}: #{dm_preview(msg)[0, 80]}") }
      DM_TYPING[:lock].synchronize { DM_TYPING[:at][key]&.delete(h) }
      track!('dm_send', h)
      { ok: true, msg: msg }
    end
  end

  # Tap a reaction: on, or off if it was yours already (one per person, like Messenger).
  route(server, '/api/dm/react') do |b, h|
    limit!("dmreact:#{h}", 300, 3600)
    e = b['e'].to_s
    raise 'bad reaction' unless e.empty? || DM_REACTS.include?(e)
    store do |d|
      key, others, = dm_thread!(d, h, b['to'])
      m = (d['dms'][key] || []).find { |x| x['id'] == b['id'].to_s && !x['gone'] } or raise 'That message is gone.'
      rx = (m['rx'] ||= {})
      e.empty? || rx[h] == e ? rx.delete(h) : rx[h] = e
      m.delete('rx') if rx.empty?
      notify!(d, m['f'], 'dm', from: h, ref: key.start_with?('c:') ? key : h, text: "#{e} @#{h} reacted to “#{dm_preview(m)[0, 50]}”") if rx[h] && m['f'] != h
      { ok: true, rx: m['rx'] || {} }
    end
  end

  # Unsend your own message: it shows as "unsent" to everyone, and its photo or voice note is deleted.
  route(server, '/api/dm/unsend') do |b, h|
    store do |d|
      key, = dm_thread!(d, h, b['to'])
      m = (d['dms'][key] || []).find { |x| x['id'] == b['id'].to_s } or raise 'That message is gone.'
      raise Forbidden, 'You can only unsend your own messages.' unless m['f'] == h
      [m['img'], m['aud']].compact.each { |u| File.delete(File.join(DM_DIR, File.basename(u))) rescue nil }
      m.keep_if { |k, _| %w[id f at].include?(k) }['gone'] = true
      { ok: true }
    end
  end

  route(server, '/api/dm/read') do |b, h|
    store do |d|
      key, = dm_thread!(d, h, b['to'])
      last = (d['dms'][key] || []).last
      r = ((d['dm_read'] ||= {})[h] ||= {})
      r[key] = [r[key].to_i, last ? last['at'] : now_ms].max
      { ok: true }
    end
  end

  route(server, '/api/dm/typing') do |b, h|
    limit!("dmtype:#{h}", 900, 3600)
    key, = store(write: false) { |d| dm_thread!(d, h, b['to']) }
    DM_TYPING[:lock].synchronize do
      DM_TYPING[:at].delete_if { |_, m| m.delete_if { |_, at| now_ms - at > 10_000 }.empty? } if DM_TYPING[:at].size > 500
      (DM_TYPING[:at][key] ||= {})[h] = now_ms
    end
    { ok: true }
  end

  # Voice note upload: raw audio bytes; the id goes into /api/dm/send as "aud".
  route(server, '/api/dm/voice', raw: true) do |_b, h, req|
    limit!("dmvoice:#{h}", 60, 3600)
    ext = DM_AUDIO[req['Content-Type'].to_s.split(';').first.to_s.strip.downcase] or raise 'Voice notes must be WebM, MP4/M4A, AAC, MP3 or Ogg audio.'
    data = req.body.to_s
    raise 'That voice note is too long (about 3 minutes max).' if data.bytesize > DM_AUDIO_MAX
    raise 'That voice note is empty.' if data.bytesize < 200
    name = "a#{SecureRandom.hex(8)}.#{ext}"
    FileUtils.mkdir_p(DM_DIR)
    File.binwrite(File.join(DM_DIR, name), data)
    MEDIA[:lock].synchronize { MEDIA[:pending][name] = { 'h' => h, 'ext' => ext, 'at' => now_ms } }
    { id: name }
  end

  # New group chat: a name and 2-30 of your friends.
  route(server, '/api/chat/new') do |b, h|
    limit!("chatnew:#{h}", 20, 3600)
    name = b['name'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 40]
    store do |d|
      fr = friends_of(d, h)
      people = Array(b['members']).map(&:to_s).uniq.select { |x| fr.include?(x) && !blocked_between(d, h).include?(x) }.first(30)
      raise 'Pick at least 2 friends for a group chat.' if people.size < 2
      name = people.first(3).map { |x| "@#{x}" }.join(', ') if name.empty?
      raise Forbidden, 'Not posted: pick another name.' unless moderate(name)
      id = SecureRandom.hex(5)
      (d['chats'] ||= {})[id] = { 'id' => id, 'name' => name, 'members' => [h] + people, 'by' => h, 'at' => now_ms }
      people.each { |x| notify!(d, x, 'dm', from: h, ref: "c:#{id}", text: "💬 @#{h} added you to #{name}") }
      { ok: true, with: "c:#{id}" }
    end
  end

  # Rename, add friends, or leave. The last one out ends the chat.
  route(server, '/api/chat/edit') do |b, h|
    limit!("chatedit:#{h}", 60, 3600)
    store do |d|
      key, _, c = dm_thread!(d, h, b['id'])
      raise 'Not a group chat.' unless c
      if b['leave']
        c['members'].delete(h)
        (d['dms'][key] ||= []) << { 'id' => "m#{SecureRandom.hex(5)}", 'f' => h, 't' => "@#{h} left", 'at' => now_ms, 'sys' => true }
        if c['members'].empty?
          d['chats'].delete(c['id']); d['dms'].delete(key)
        end
        next { ok: true, left: true }
      end
      if b['name']
        n = b['name'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 40]
        raise 'Give it a name.' if n.empty?
        raise Forbidden, 'Not posted: pick another name.' unless moderate(n)
        c['name'] = n
        (d['dms'][key] ||= []) << { 'id' => "m#{SecureRandom.hex(5)}", 'f' => h, 't' => "@#{h} named the chat #{n}", 'at' => now_ms, 'sys' => true }
      end
      fr = friends_of(d, h)
      add = Array(b['add']).map(&:to_s).uniq.select { |x| fr.include?(x) && !c['members'].include?(x) }.first(30 - c['members'].size + 1)
      unless add.empty?
        c['members'] += add
        (d['dms'][key] ||= []) << { 'id' => "m#{SecureRandom.hex(5)}", 'f' => h, 't' => "@#{h} added #{add.map { |x| "@#{x}" }.join(', ')}", 'at' => now_ms, 'sys' => true }
        add.each { |x| notify!(d, x, 'dm', from: h, ref: key, text: "💬 @#{h} added you to #{c['name']}") }
      end
      { ok: true, chat: c }
    end
  end

  # Photos and voice notes: random ids, served only to the people in the chat (and a voice note to its uploader
  # before it's sent); unsent ones are deleted. A signed-in stranger with the link gets a 404.
  { '/dm-img' => [/\A\/dm-img\/(i[0-9a-f]{16}\.jpg)\z/, 'image/jpeg'], '/dm-aud' => [/\A\/dm-aud\/(a[0-9a-f]{16}\.(webm|m4a|aac|mp3|ogg))\z/, nil] }.each do |path, (re, type)|
    server.mount_proc(path) do |req, res|
      name = req.path[re, 1]
      file = name && File.join(DM_DIR, name)
      next res.status = 404 unless file && File.file?(file) && dm_media_ok?(session_user(req), "#{path}/#{name}", name)
      res['Content-Type'] = type || DM_AUDIO.key(File.extname(name)[1..]) || 'application/octet-stream'
      res['Cache-Control'] = 'private, max-age=86400'
      res['Accept-Ranges'] = 'bytes'
      size = File.size(file)
      a, z = req['Range'].to_s.match(/\Abytes=(\d*)-(\d*)\z/)&.captures   # iPhones only play audio they can fetch in pieces
      if a
        first = a.empty? ? [size - z.to_i, 0].max : a.to_i
        last = z.empty? || a.empty? ? size - 1 : [z.to_i, size - 1].min
        next (res.status = 416; res['Content-Range'] = "bytes */#{size}") if first > last || first >= size
        res.status = 206
        res['Content-Range'] = "bytes #{first}-#{last}/#{size}"
        res.body = File.open(file, 'rb') { |f| f.seek(first); f.read(last - first + 1) }
      else
        res.body = File.binread(file)
      end
    end
  end
end

# Is h in a chat that has this photo / voice note? Thread "a|b" = those two; "c:<id>" = that group chat's members now.
def dm_media_ok?(h, url, name)
  return false unless h
  return true if MEDIA[:lock].synchronize { MEDIA[:pending][name]&.dig('h') == h }
  STORE[:lock].synchronize do
    d = STORE[:d]
    (d['dms'] || {}).any? do |key, msgs|
      who = key.start_with?('c:') ? Array(d.dig('chats', key[2..], 'members')) : key.split('|')
      who.include?(h) && msgs.any? { |m| m['img'] == url || m['aud'] == url }
    end
  end
end

# ---- Plans with friends: a group chat with a plan pinned on top (c['plan']). Options are events, places or ideas
# (2-6), times are optional (up to 4); everyone votes for as many as work; the organizer locks one in, then it's a
# calendar event with a going list. Same members and rules as the chat it lives in.
def plan_opt_clean(o)
  return nil unless o.is_a?(Hash)
  name = o['name'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 80]
  return nil if name.empty?
  { 'id' => SecureRandom.hex(3), 'k' => %w[event place idea].include?(o['k']) ? o['k'] : 'idea', 'name' => name, 'sub' => o['sub'].to_s.gsub(/[[:cntrl:]]/, ' ')[0, 80],
    'ref' => o['ref'].to_s[0, 60], 'e' => o['e'].to_s[0, 4], 'at' => o['at'].to_i.positive? ? o['at'].to_i : nil,
    'lat' => (Float(o['lat']) rescue nil), 'lng' => (Float(o['lng']) rescue nil), 'votes' => [] }.compact.reject { |_, v| v == '' }
end

def plan_post!(d, key, h, text)
  (d['dms'][key] ||= []) << { 'id' => "m#{SecureRandom.hex(5)}", 'f' => h, 't' => text, 'at' => now_ms, 'sys' => true }
end

# Locked-in plans: a nudge two hours before (to everyone going), and a nudge to the organizer if the vote has sat
# open for a day. Called with the event reminders, every 5 minutes.
def plan_remind!
  t = now_ms
  store do |d|
    (d['chats'] || {}).each_value do |c|
      pl = c['plan'] or next
      key = "c:#{c['id']}"
      if pl['status'] == 'set' && (at = pl.dig('pick', 'at').to_i) > t && at < t + 2 * 3_600_000 && !pl['reminded']
        pl['reminded'] = t
        o = pl['opts'].find { |x| x['id'] == pl.dig('pick', 'opt') } || {}
        (pl['going'] || []).each do |h|
          notify!(d, h, 'remind', ref: key, text: "⏰ #{pl['title']} at #{Time.at(at / 1000).strftime('%-l:%M %p')}: #{o['name']}")
        end
      elsif pl['status'] == 'voting' && pl['at'].to_i < t - 86_400_000 && !pl['nudged']
        pl['nudged'] = t
        n = (pl['opts'].flat_map { |o| o['votes'].to_a } + pl['times'].flat_map { |x| x['votes'].to_a }).uniq.size
        next if n < 2
        notify!(d, pl['by'], 'dm', ref: key, text: "🗳️ #{n} #{n == 1 ? 'person has' : 'people have'} voted on #{pl['title']}. Lock in the top pick?")
      end
    end
  end
end

def mount_plans(server)
  route(server, '/api/hangout/new') do |b, h|
    limit!("hangout:#{h}", 20, 3600)
    title = b['title'].to_s.gsub(/[[:cntrl:]]/, ' ').strip[0, 60]
    opts = Array(b['opts']).map { |o| plan_opt_clean(o) }.compact.first(6)
    times = Array(b['times']).map(&:to_i).select { |t| t > now_ms - 3_600_000 && t < now_ms + 400 * 86_400_000 }.uniq.sort.first(4)
    raise 'Name the plan, e.g. Saturday night.' if title.empty?
    raise 'Add at least one option to vote on.' if opts.empty?
    raise Forbidden, 'Not posted: please reword that.' unless moderate([title, *opts.map { |o| o['name'] }].join(' · '))
    store do |d|
      fr = friends_of(d, h)
      people = Array(b['members']).map(&:to_s).uniq.select { |x| fr.include?(x) && !blocked_between(d, h).include?(x) }.first(30)
      raise 'Invite at least one friend.' if people.empty?
      id = SecureRandom.hex(5)
      plan = { 'title' => title, 'opts' => opts, 'times' => times.map { |t| { 'at' => t, 'votes' => [] } }, 'by' => h, 'status' => 'voting', 'going' => [], 'at' => now_ms }
      (d['chats'] ||= {})[id] = { 'id' => id, 'name' => "📅 #{title}", 'members' => [h] + people, 'by' => h, 'at' => now_ms, 'plan' => plan }
      plan_post!(d, "c:#{id}", h, "@#{h} started a plan: vote for what works")
      people.each { |x| notify!(d, x, 'dm', from: h, ref: "c:#{id}", text: "📅 @#{h} wants to make plans: #{title}. Vote on what works!") }
      track!('hangout_new', h)
      { ok: true, with: "c:#{id}" }
    end
  end

  # Vote (for as many options and times as work), lock one in (the organizer), say you're going, or add an option.
  route(server, '/api/hangout/act') do |b, h|
    limit!("hangoutact:#{h}", 400, 3600)
    store do |d|
      key, others, c = dm_thread!(d, h, b['id'])
      pl = c && c['plan'] or raise 'No plan in this chat.'
      case b['do']
      when 'vote'
        x = (b['time'] ? pl['times'][b['time'].to_i] : pl['opts'].find { |o| o['id'] == b['opt'].to_s }) or raise 'No such choice.'
        raise "It's already decided." if pl['status'] == 'set'
        v = (x['votes'] ||= [])
        v.include?(h) ? v.delete(h) : v << h
      when 'add'
        raise "It's already decided." if pl['status'] == 'set'
        o = plan_opt_clean(b['opt']) or raise 'Name the option.'
        raise Forbidden, 'Not posted: please reword that.' unless moderate(o['name'])
        raise 'That is plenty of options (6).' if pl['opts'].size >= 6
        o['votes'] = [h]
        pl['opts'] << o
        plan_post!(d, key, h, "@#{h} added #{o['name']}")
      when 'lock'
        raise Forbidden, 'Only the person who started the plan can lock it in.' unless pl['by'] == h
        o = pl['opts'].find { |x| x['id'] == b['opt'].to_s } or raise 'Pick the winning option.'
        t = b['time'] && pl['times'][b['time'].to_i]
        at = t ? t['at'] : o['at']
        pl.delete('reminded')
        pl.merge!('status' => 'set', 'pick' => { 'opt' => o['id'], 'at' => at }.compact, 'going' => ([h] + o['votes'].to_a).uniq & c['members'])
        when_s = at ? Time.at(at / 1000).strftime('%a %b %-d, %-l:%M %p') : nil
        plan_post!(d, key, h, "📅 It's on: #{o['name']}#{when_s ? " · #{when_s}" : ''}")
        did_something!(d, h, 'plan')
        others.each { |x| notify!(d, x, 'dm', from: h, ref: key, text: "📅 It's on: #{pl['title']}: #{o['name']}#{when_s ? " · #{when_s}" : ''}") }
      when 'unlock'
        raise Forbidden, 'Only the person who started the plan can change it.' unless pl['by'] == h
        pl['status'] = 'voting'; pl.delete('pick')
        plan_post!(d, key, h, "@#{h} reopened the vote")
      when 'going'
        raise 'Lock in a plan first.' unless pl['status'] == 'set'
        g = (pl['going'] ||= [])
        b['on'] ? (g << h unless g.include?(h)) : g.delete(h)
      else raise 'bad action'
      end
      { ok: true, plan: pl }
    end
  end
end
