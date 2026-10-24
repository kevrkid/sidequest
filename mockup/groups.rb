# Groups, Facebook-Groups-style, on top of d['groups'] / d['members']: a wall (d['gposts'][gid]) of posts with a photo,
# polls and group events (RSVP "going"), likes and comments, pinned posts; admins (g['admins'], the owner always is
# one) who pin, remove posts and members, approve join requests (d['greqs'][gid]) and edit the group; private groups
# (g['priv']) whose wall, chat and member list only members see. New posts notify members (kind 'group').
GROUP_DIR = File.join(__dir__, 'data', 'groups')
GPOST_MAX = 300

def group!(d, gid)
  g = d['groups'][gid.to_s[0, 20]]
  raise 'No such group.' unless g && !g['removed']
  g
end

def group_member?(d, g, h) (d['members'][g['id']] || []).include?(h) end
def group_admin?(g, h) h && (g['owner'] == h || (g['admins'] || []).include?(h)) end

def group_role(d, g, h)
  return 'owner' if g['owner'] == h
  return 'admin' if (g['admins'] || []).include?(h) && group_member?(d, g, h)
  return 'member' if group_member?(d, g, h)
  ((d['greqs'] || {})[g['id']] || []).include?(h) ? 'requested' : 'none'
end

def group_can_read!(d, g, h)
  raise Forbidden, 'This group is private. Join to see what they post.' if g['priv'] && !group_member?(d, g, h)
end

def group_must_be_member!(d, g, h)
  raise Forbidden, 'Join the group first.' unless group_member?(d, g, h)
end

def gpost!(d, g, pid)
  ((d['gposts'] ||= {})[g['id']] ||= []).find { |p| p['id'] == pid.to_s && !p['removed'] } or raise 'That post is gone.'
end

# A post as a phone sees it: like count and whether you liked it, votes per option and yours, who's going.
def gpost_out(p, h, hidden)
  out = p.reject { |k, _| %w[likes removed].include?(k) }
  likes = (p['likes'] || []).reject { |x| hidden.include?(x) }
  out['likes'] = likes.size
  out['liked'] = likes.include?(h)
  out['comments'] = (p['comments'] || []).reject { |c| c['removed'] || hidden.include?(c['u']) }
  if p['poll']
    out['poll'] = p['poll'].merge('opts' => p['poll']['opts'].map { |o| { 't' => o['t'], 'n' => (o['votes'] || []).size, 'mine' => (o['votes'] || []).include?(h) } })
  end
  out['going'] = (p['going'] || []).reject { |x| hidden.include?(x) } if p['ev']
  out
end

def group_notify_members!(d, g, from, text, ref)
  (d['members'][g['id']] || []).first(200).each { |x| notify!(d, x, 'group', from: from, ref: "g:#{g['id']}", text: text) }
end

def mount_groups(server)
  # The group page: the wall (pinned first, newest next), your role, and for admins the join requests.
  route(server, '/api/group/feed') do |b, h|
    store(write: false) do |d|
      g = group!(d, b['id'])
      role = group_role(d, g, h)
      hidden = blocked_between(d, h)
      base = { group: g.reject { |k, _| k == 'unreviewed' }, role: role, mcount: (d['members'][g['id']] || []).size }
      next base.merge(locked: true, posts: []) if g['priv'] && !group_member?(d, g, h)
      posts = ((d['gposts'] || {})[g['id']] || []).reject { |p| p['removed'] || hidden.include?(p['u']) }
      posts = posts.sort_by { |p| [p['pinned'] ? 0 : 1, -p['at']] }.first(60).map { |p| gpost_out(p, h, hidden) }
      base.merge(posts: posts, members: (d['members'][g['id']] || []).reject { |x| hidden.include?(x) },
                 admins: [g['owner'], *(g['admins'] || [])].compact.uniq,
                 requests: group_admin?(g, h) ? ((d['greqs'] || {})[g['id']] || []) : nil).compact
    end
  end

  # New post: text (+ photo), a poll (2-6 options) or a group event (title, time, place).
  route(server, '/api/group/post') do |b, h|
    limit!("gpost:#{h}", 40, 3600)
    text = b['t'].to_s.strip[0, 2000]
    img = b['img'].to_s
    raise 'Photo too large.' if img.size > 700_000
    raw = img.empty? ? nil : (img[%r{\Adata:image/jpeg;base64,([A-Za-z0-9+/=]+)\z}, 1] or raise 'Photos must be JPEG.')
    poll = nil
    if b['poll'].is_a?(Hash)
      q = b['poll']['q'].to_s.strip[0, 140]
      opts = Array(b['poll']['opts']).map { |o| o.to_s.strip[0, 60] }.reject(&:empty?).uniq.first(6)
      raise 'A poll needs a question and at least 2 choices.' if q.empty? || opts.size < 2
      poll = { 'q' => q, 'opts' => opts.map { |o| { 't' => o, 'votes' => [] } }, 'multi' => !!b['poll']['multi'] }
    end
    ev = nil
    if b['ev'].is_a?(Hash)
      title = b['ev']['title'].to_s.strip[0, 80]
      at = b['ev']['at'].to_i
      raise 'Give the event a name.' if title.empty?
      raise 'Pick a time in the future.' unless at > now_ms - 3_600_000 && at < now_ms + 400 * 86_400_000
      ev = { 'title' => title, 'at' => at, 'place' => spot_ref(b['ev']['place']) }.compact
    end
    raise 'Write something first.' if text.empty? && !raw && !poll && !ev
    reviewed = moderate([text, poll && poll['q'], *(poll ? poll['opts'].map { |o| o['t'] } : []), ev && ev['title'], ev && ev['place'].is_a?(Hash) ? ev['place']['name'] : nil].compact.join(' · '))
    store do |d|
      g = group!(d, b['id'])
      group_must_be_member!(d, g, h)
      p = { 'id' => "q#{SecureRandom.hex(5)}", 'u' => h, 't' => text, 'at' => now_ms, 'likes' => [], 'comments' => [] }
      if raw
        FileUtils.mkdir_p(GROUP_DIR)
        name = "p#{SecureRandom.hex(8)}.jpg"
        File.binwrite(File.join(GROUP_DIR, name), raw.unpack1('m'))
        p['img'] = "/group-img/#{name}"
      end
      p['poll'] = poll if poll
      if ev
        p['ev'] = ev
        p['going'] = [h]
      end
      p['unreviewed'] = true unless reviewed
      list = ((d['gposts'] ||= {})[g['id']] ||= [])
      list << p
      list.shift while list.size > GPOST_MAX
      what = ev ? "📅 #{ev['title']}" : poll ? "📊 #{poll['q']}" : text.empty? ? '📷 a photo' : text
      group_notify_members!(d, g, h, "#{ev ? '📅' : poll ? '📊' : '🏘️'} @#{h} in #{g['n'].to_s[0, 40]}: #{what[0, 80]}", p['id'])
      track!('group_post', h)
      { ok: true, post: gpost_out(p, h, Set.new) }
    end
  end

  # Like, comment, vote, going: members only.
  route(server, '/api/group/act') do |b, h|
    limit!("gact:#{h}", 400, 3600)
    text = b['t'].to_s.strip[0, 600]
    flagged = b['do'] == 'comment' && !text.empty? && !moderate(text)
    store do |d|
      g = group!(d, b['id'])
      group_must_be_member!(d, g, h)
      p = gpost!(d, g, b['pid'])
      case b['do']
      when 'like'
        l = (p['likes'] ||= [])
        l.include?(h) ? l.delete(h) : (l << h; notify!(d, p['u'], 'group', from: h, ref: "g:#{g['id']}", text: "👍 @#{h} liked your post in #{g['n'].to_s[0, 40]}"))
      when 'comment'
        raise 'Write a comment first.' if text.empty?
        (p['comments'] ||= []) << { 'id' => "k#{SecureRandom.hex(4)}", 'u' => h, 't' => text, 'at' => now_ms, 'unreviewed' => flagged }.reject { |_, v| v == false }
        p['comments'].shift while p['comments'].size > 200
        ([p['u']] + p['comments'].map { |c| c['u'] }).uniq.first(30).each do |x|
          notify!(d, x, 'group', from: h, ref: "g:#{g['id']}", text: "💬 @#{h} commented in #{g['n'].to_s[0, 40]}: #{text[0, 70]}")
        end
      when 'uncomment'
        c = (p['comments'] || []).find { |x| x['id'] == b['cid'].to_s } or raise 'That comment is gone.'
        raise Forbidden, 'Only the writer or an admin can remove this.' unless c['u'] == h || group_admin?(g, h)
        c['removed'] = true
      when 'vote'
        raise 'Not a poll.' unless p['poll']
        o = p['poll']['opts'][b['opt'].to_i] or raise 'No such choice.'
        mine = (o['votes'] ||= []).include?(h)
        p['poll']['opts'].each { |x| (x['votes'] ||= []).delete(h) } unless p['poll']['multi']
        mine ? o['votes'].delete(h) : o['votes'] << h
      when 'going'
        raise 'Not an event.' unless p['ev']
        gl = (p['going'] ||= [])
        b['on'] ? (gl << h unless gl.include?(h)) : gl.delete(h)
        notify!(d, p['u'], 'group', from: h, ref: "g:#{g['id']}", text: "📅 @#{h} is going to #{p['ev']['title'][0, 50]}") if b['on']
      else raise 'bad action'
      end
      { ok: true, post: gpost_out(p, h, blocked_between(d, h)) }
    end
  end

  # Admin tools, and removing your own post.
  route(server, '/api/group/admin') do |b, h|
    limit!("gadmin:#{h}", 200, 3600)
    store do |d|
      g = group!(d, b['id'])
      admin = group_admin?(g, h) && group_member?(d, g, h)
      case b['do']
      when 'remove'   # a post: its writer or an admin
        p = gpost!(d, g, b['pid'])
        raise Forbidden, 'Only the writer or an admin can remove this.' unless p['u'] == h || admin
        File.delete(File.join(GROUP_DIR, File.basename(p['img']))) rescue nil if p['img']
        p['removed'] = true
      when 'pin'
        raise Forbidden, 'Only admins can pin posts.' unless admin
        p = gpost!(d, g, b['pid'])
        b['on'] ? p['pinned'] = true : p.delete('pinned')
      when 'approve', 'decline'
        raise Forbidden, 'Only admins can answer join requests.' unless admin
        reqs = ((d['greqs'] ||= {})[g['id']] ||= [])
        who = b['who'].to_s
        raise 'No such request.' unless reqs.delete(who)
        if b['do'] == 'approve' && d['users'][who]
          m = (d['members'][g['id']] ||= [])
          m << who unless m.include?(who)
          notify!(d, who, 'group', from: h, ref: "g:#{g['id']}", text: "✅ You're in! @#{h} approved you for #{g['n'].to_s[0, 40]}")
        end
      when 'admin'   # the owner makes or unmakes admins
        raise Forbidden, 'Only the person who started the group can choose admins.' unless g['owner'] == h
        who = b['who'].to_s
        raise 'They need to be a member first.' unless group_member?(d, g, who)
        a = (g['admins'] ||= [])
        b['on'] ? (a << who unless a.include?(who)) : a.delete(who)
        notify!(d, who, 'group', from: h, ref: "g:#{g['id']}", text: "⭐ @#{h} made you an admin of #{g['n'].to_s[0, 40]}") if b['on']
      when 'kick'
        raise Forbidden, 'Only admins can remove members.' unless admin
        who = b['who'].to_s
        raise Forbidden, "The group's owner can't be removed." if who == g['owner']
        raise Forbidden, 'Only the owner can remove an admin.' if (g['admins'] || []).include?(who) && g['owner'] != h
        (d['members'][g['id']] || []).delete(who)
        (g['admins'] || []).delete(who)
      when 'delete'   # the owner ends the group: wall, photos, chat and members go
        raise Forbidden, 'Only the person who started the group can delete it.' unless g['owner'] == h
        ((d['gposts'] || {}).delete(g['id']) || []).each { |p| File.delete(File.join(GROUP_DIR, File.basename(p['img']))) rescue nil if p['img'] }
        File.delete(File.join(GROUP_DIR, File.basename(g['cover']))) rescue nil if g['cover']
        (d['ev_chat'] || {}).delete("g:#{g['id']}")
        (d['greqs'] || {}).delete(g['id'])
        d['members'][g['id']] = []
        g.keep_if { |k, _| %w[id n owner created].include?(k) }['removed'] = true
        next { ok: true, deleted: true }
      when 'settings'
        raise Forbidden, 'Only admins can change the group.' unless admin
        if b.key?('d')
          desc = b['d'].to_s.strip[0, 300]
          raise Forbidden, 'Not saved: please reword that.' unless desc == g['d'].to_s || moderate(desc)   # only new words get checked
          g['d'] = desc
        end
        g['priv'] = !!b['priv'] if b.key?('priv')
        g['e'] = b['e'].to_s[0, 4] if b['e'].to_s.size.between?(1, 4)
        if b.key?('rules')
          rules = Array(b['rules']).map { |r| r.to_s.strip[0, 140] }.reject(&:empty?).first(10)
          raise Forbidden, 'Not saved: please reword the rules.' unless rules == (g['rules'] || []) || moderate(rules.join(' · '))
          g['rules'] = rules
        end
        if b['cover'].to_s.start_with?('data:')
          raw = b['cover'][%r{\Adata:image/jpeg;base64,([A-Za-z0-9+/=]+)\z}, 1] or raise 'Photos must be JPEG.'
          raise 'Photo too large.' if raw.size > 700_000
          FileUtils.mkdir_p(GROUP_DIR)
          File.delete(File.join(GROUP_DIR, File.basename(g['cover']))) rescue nil if g['cover']
          name = "c#{SecureRandom.hex(8)}.jpg"
          File.binwrite(File.join(GROUP_DIR, name), raw.unpack1('m'))
          g['cover'] = "/group-img/#{name}"
        elsif b['cover'] == ''
          File.delete(File.join(GROUP_DIR, File.basename(g['cover']))) rescue nil if g['cover']
          g.delete('cover')
        end
      else raise 'bad action'
      end
      { ok: true, group: g.reject { |k, _| k == 'unreviewed' } }
    end
  end

  # Post photos and covers: random names; a private group's photos only to its members.
  server.mount_proc('/group-img') do |req, res|
    name = req.path[%r{\A/group-img/([pc][0-9a-f]{16}\.jpg)\z}, 1]
    file = name && File.join(GROUP_DIR, name)
    next res.status = 404 unless file && File.file?(file)
    viewer = session_user(req)   # before the store lock: it takes the same lock
    ok = store(write: false) do |d|
      g = d['groups'].values.find { |x| x['cover'] == "/group-img/#{name}" } ||
          d['groups'].values.find { |x| ((d['gposts'] || {})[x['id']] || []).any? { |p| p['img'] == "/group-img/#{name}" } }
      g && (!g['priv'] || name.start_with?('c') || group_member?(d, g, viewer))
    end
    next res.status = 404 unless ok
    res['Content-Type'] = 'image/jpeg'
    res['Cache-Control'] = 'private, max-age=86400'
    res.body = File.binread(file)
  end
end
