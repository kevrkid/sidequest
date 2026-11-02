# "I'm out tonight": one tap tells your friends you're going out and what you're down for (drinks, dancing, pool…),
# when, and roughly where (a hot spot, never a spot on the map). Friends get one notification a night and can tap
# "I'm down"; you hear about it and can open a chat. It ends at 5 AM.
#   d['outn'][h] = { 'acts' => [keys], 'when' => 'now'|'20'..'23', 'zone' => hot spot id | nil, 'at', 'until', 'told',
#                    'down' => { handle => ms } }
# Only friends see it (and never across a block); picks only, no free text, so there's nothing to moderate.
OUT_ACTS = %w[drinks dancing music pool food karaoke comedy chill sports active anything].freeze
OUT_WHEN = %w[now 19 20 21 22 23].freeze

def out_night_end(t = Time.now)   # 5 AM after tonight (Austin time; the server runs with TZ=America/Chicago)
  five = Time.new(t.year, t.month, t.day, 5, 0, 0)
  (t < five ? five : five + 86_400).to_f * 1000
end

def out_active(d, h)
  o = (d['outn'] || {})[h]
  o && o['until'].to_i > now_ms ? o : nil
end

# What a viewer sees: their own status (with who's down) and their friends' (count, and whether they're in).
def out_view(d, h)
  hidden = blocked_between(d, h)
  zone = ->(z) { (Places::HOTSPOTS.find { |x| x[:id] == z } || {})[:name] }
  mine = out_active(d, h)
  friends = friends_of(d, h).to_a.reject { |f| hidden.include?(f) }.map do |f|
    o = out_active(d, f) or next
    downs = (o['down'] || {}).keys.reject { |x| hidden.include?(x) }
    { h: f, acts: o['acts'], when: o['when'], zone: o['zone'], zname: zone.(o['zone']), at: o['at'],
      downs: downs.size, mine: downs.include?(h), friends_down: downs & friends_of(d, h).to_a }
  end.compact.sort_by { |x| -x[:at] }
  me = mine && { acts: mine['acts'], when: mine['when'], zone: mine['zone'], zname: zone.(mine['zone']), at: mine['at'], until: mine['until'],
                 down: (mine['down'] || {}).keys.reject { |x| hidden.include?(x) } }
  { me: me, friends: friends }
end

def out_label(o)
  acts = (o['acts'] || []).first(3).join(', ')
  w = o['when'] == 'now' ? 'now' : "around #{o['when'].to_i - 12} PM"
  "#{acts.empty? ? 'out' : acts} · #{w}"
end

def mount_outnight(server)
  route(server, '/api/out') do |b, h|
    limit!("out:#{h}", 12, 3600)
    acts = (b['acts'].is_a?(Array) ? b['acts'] : []).map(&:to_s).select { |a| OUT_ACTS.include?(a) }.uniq.first(4)
    raise 'Pick what you\'re down for.' if acts.empty?
    w = OUT_WHEN.include?(b['when'].to_s) ? b['when'].to_s : 'now'
    z = b['zone'].to_s.empty? ? nil : (Places::HOTSPOTS.find { |x| x[:id] == b['zone'].to_s } or raise 'Unknown area.')[:id]
    store do |d|
      o = out_active(d, h) || { 'down' => {}, 'told' => ((d['outn'] || {})[h] || {})['told'] }   # turning it off and on again doesn't ping twice
      o.merge!('acts' => acts, 'when' => w, 'zone' => z, 'at' => now_ms, 'until' => out_night_end)
      (d['outn'] ||= {})[h] = o
      if o['told'].to_i < now_ms - 12 * 3_600_000   # friends hear once a night, not on every edit
        o['told'] = now_ms
        friends_of(d, h).each { |f| notify!(d, f, 'out', from: h, ref: "o:#{h}", text: "🌙 @#{h} is out tonight: #{out_label(o)}. Down?") }
      end
      track!('out_set', h)
      out_view(d, h)
    end
  end

  route(server, '/api/out/off') do |_b, h|
    store { |d| o = (d['outn'] || {})[h]; o['until'] = 0 if o; out_view(d, h) }   # kept till tomorrow so a re-post doesn't ping again
  end

  # "I'm down" on a friend's night (on: false takes it back)
  route(server, '/api/out/down') do |b, h|
    limit!("outdown:#{h}", 40, 3600)
    f = b['h'].to_s
    store do |d|
      o = out_active(d, f)
      raise 'They\'re not out tonight any more.' unless o && friends_of(d, h).include?(f) && !blocked_between(d, h).include?(f)
      if b['on'] == false
        (o['down'] ||= {}).delete(h)
      elsif !(o['down'] ||= {}).key?(h)
        o['down'][h] = now_ms
        notify!(d, f, 'down', from: h, ref: "o:#{f}", text: "🙌 @#{h} is down to go out tonight")
        track!('out_down', h)
      end
      out_view(d, h)
    end
  end
end
