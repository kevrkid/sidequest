# Scout gets to know each person: a running conversation (so it can hold a real back-and-forth across visits and
# devices), short notes it decides to remember ("vegetarian", "plays goalie", "new to Austin"), what they ordered and
# how they rated it, and a personality picked to suit theirs. All of it is private to that person: only their own
# Scout reads it, they can see and delete every note (You → Scout), and it goes with the account.
#   d['scout_mem'][h] = { 'log' => [{w: 'u'|'s', t, at}], 'notes' => [{t, at}], 'turns' => n, 'since' => ms }
#   d['ratings'][place id][h] = { s: 1-5, dish, note, at }      (everyone's, averaged on place cards)
#   d['orders'][h] = [{ id, name, dish, s, note, at }]           (theirs: "what did I get at Veracruz last time?")

SCOUT_LOG_MAX = 40     # turns kept (both sides), the newest 12 go to Claude
SCOUT_NOTES_MAX = 60

# Personalities. `auto` picks one from the person's 16-type quiz result; they can choose any time.
SCOUT_PERSONAS = {
  'buddy'   => { name: 'Easygoing buddy', e: '😎', how: 'Warm, relaxed and casual, like a friend who knows the city. Light humor now and then.' },
  'hype'    => { name: 'Hype crew', e: '🔥', how: 'Upbeat and energetic. Celebrate their plans, keep it punchy, one emoji is fine. Never loud when they are stressed.' },
  'chill'   => { name: 'Chill local', e: '🌙', how: 'Calm, low-key and brief. Fewest words that help. Dry humor, never pushy, never gushing.' },
  'planner' => { name: 'Planner', e: '🗓️', how: 'Organized and crisp: the answer, a time or two, the next step. No fluff, no small talk unless they start it.' },
  'curious' => { name: 'Storyteller', e: '📖', how: 'Thoughtful and curious: share a small story or fact when it fits, and ask one good question back.' }
}.freeze

def scout_persona_for(choice, type)
  return choice if SCOUT_PERSONAS.key?(choice)
  t = type.to_s.upcase
  return 'buddy' unless t =~ /\A[EI][NS][TF][JP]\z/
  return 'planner' if t[2] == 'T' && t[3] == 'J'
  return 'chill' if t[0] == 'I' && t[2] == 'T'
  return 'curious' if t[0] == 'I' && t[1] == 'N'
  return 'hype' if t[0] == 'E' && t[3] == 'P'
  'buddy'
end

def scout_mem(d, h)
  ((d['scout_mem'] ||= {})[h] ||= { 'log' => [], 'notes' => [], 'turns' => 0, 'since' => now_ms })
end

def scout_note_ok(t)
  t = t.to_s.gsub(/\s+/, ' ').strip[0, 140]
  t.size >= 3 && t !~ /\b(password|passcode|ssn|social security|credit card|card number|\d{3}-\d{2}-\d{4})\b/i ? t : nil
end

# After each answer: the turn goes in the log, new notes are added (no repeats), and the turn count grows.
def scout_remember!(d, h, q, say, notes)
  m = scout_mem(d, h)
  m['log'] << { 'w' => 'u', 't' => q.to_s[0, 300], 'at' => now_ms } << { 'w' => 's', 't' => say.to_s[0, 600], 'at' => now_ms }
  m['log'].shift while m['log'].size > SCOUT_LOG_MAX
  have = m['notes'].map { |n| n['t'].downcase }
  Array(notes).first(3).map { |n| scout_note_ok(n) }.compact.each do |n|
    next if have.include?(n.downcase)
    m['notes'] << { 't' => n, 'at' => now_ms }; have << n.downcase
  end
  m['notes'].shift while m['notes'].size > SCOUT_NOTES_MAX
  m['turns'] += 1
end

def scout_forget!(d, h)
  (d['scout_mem'] || {}).delete(h)
  (d['orders'] || {}).delete(h)
  (d['ratings'] || {}).each_value { |r| r.delete(h) }
end

# What goes in Scout's prompt about this person.
def scout_mind_prompt(d, h, persona)
  m = scout_mem(d, h)
  p = SCOUT_PERSONAS[persona]
  orders = (d['orders'] || {})[h].to_a.last(8).map { |o| "#{o['dish'] || 'something'} at #{o['name']}#{o['s'] ? " (#{o['s']}★)" : ''}" }
  days = ((now_ms - m['since'].to_i) / 86_400_000.0).floor
  <<~M
    Your personality right now: #{p[:name]} (#{persona}). #{p[:how]} The person can switch it in You → Scout; the others are
    #{SCOUT_PERSONAS.reject { |k, _| k == persona }.map { |k, x| "#{x[:name]} (#{k})" }.join(', ')}.
    You've talked with this person #{m['turns']} time#{m['turns'] == 1 ? '' : 's'}#{days.positive? ? " over #{days} day#{days == 1 ? '' : 's'}" : ''}.#{m['turns'] < 5 ? ' You are still new to each other: keep it extra short and friendly, one idea or question at a time.' : ''}
    #{m['notes'].any? ? "What you remember about them (private to them; use it naturally, don't recite it): #{JSON.generate(m['notes'].last(40).map { |n| n['t'] })}" : 'You don\'t know much about them yet.'}
    #{orders.any? ? "What they've ordered and rated (newest last): #{orders.join('; ')}" : ''}
  M
end

# The setup interview: what the app still needs to know, from the phone (it holds the quiz and profile questions).
def scout_interview_prompt(iv)
  return '' unless iv.is_a?(Hash)
  quiz = Array(iv['quiz']).first(4).select { |x| x.is_a?(Hash) }.map { |x| { i: x['i'].to_i, statement: x['text'].to_s[0, 120] } }
  # About-you keys are camelCase (kidWas, sportsPlay); `many` questions take several answers, the person's own words too
  life = Array(iv['life']).first(4).select { |x| x.is_a?(Hash) && x['k'].to_s =~ /\A[A-Za-z_]{1,30}\z/ }
                          .map { |x| { k: x['k'].to_s, q: x['q'].to_s[0, 120], options: Array(x['opts']).first(30).map { |o| o.to_s[0, 40] }, many: x['many'] == true } }
  have = Array(iv['interests']).first(30).map { |x| x.to_s[0, 30] }
  opts = Array(iv['interest_options']).first(40).map { |x| x.to_s[0, 30] }
  <<~I
    SETUP INTERVIEW: you are welcoming a new member and setting up their profile by chatting, one short question at a time.
    Order: their interests (until they have 3 or more), then the personality statements, then the about-you questions.
    In your first message, say in one short sentence that you're their AI assistant and will ask a few easy questions, then ask the first one.
    Use plain, everyday words that are easy to understand.
    Ask each one casually in your own words, never as a form, and react to their answer in a few words before the next.
    Put everything you learned in `profile`: `interests` (from these options when one fits, else their own word, max 30
    letters: #{JSON.generate(opts)}; they already have #{JSON.generate(have)}), `quiz` items {i, v} where v is 1 (strongly
    disagree) to 5 (strongly agree) with the statement, and `life` items {k, v} (v must be one of the options when there
    are options; for a question with `many`, v can name several, separated by commas, and their own words are fine
    too, a few words each). Only record what they actually said. They can skip anything ("skip", "next", "rather not")
    and stop any time; if they stop or nothing is left, set `profile.done` true, say they're all set and that they can talk to you any
    time with the compass button. Answer their questions about the app or their account along the way, then carry on.
    Personality statements still open: #{JSON.generate(quiz)}
    About-you questions still open: #{JSON.generate(life)}
  I
end

def scout_profile_clean(p)
  return nil unless p.is_a?(Hash)
  out = {
    'interests' => Array(p['interests']).first(8).map { |x| x.to_s.strip[0, 30] }.reject(&:empty?),
    'quiz' => Array(p['quiz']).first(6).select { |x| x.is_a?(Hash) && x['i'].to_i.between?(0, 19) && x['v'].to_i.between?(1, 5) }
                .map { |x| { 'i' => x['i'].to_i, 'v' => x['v'].to_i } },
    'life' => Array(p['life']).first(6).select { |x| x.is_a?(Hash) && x['k'].to_s =~ /\A[A-Za-z_]{1,30}\z/ && !x['v'].to_s.strip.empty? }
                .map { |x| { 'k' => x['k'].to_s, 'v' => x['v'].to_s.strip[0, 200] } },
    'done' => p['done'] == true
  }
  out.values.any? { |v| v == true || v.is_a?(Array) && v.any? } ? out : nil
end

def place_rating(d, id)
  r = (d['ratings'] || {})[id] or return nil
  s = r.values.map { |x| x['s'].to_i }.select { |x| x.between?(1, 5) }
  s.empty? ? nil : { avg: (s.sum.to_f / s.size).round(1), n: s.size }
end

def mount_scout_mind(server)
  # Everything Scout remembers about you, to look at and delete
  route(server, '/api/scout/memory', get: true) do |_b, h, _req|
    store(write: false) do |d|
      m = (d['scout_mem'] || {})[h] || {}
      { notes: Array(m['notes']).each_with_index.map { |n, i| { i: i, t: n['t'], at: n['at'] } }.reverse,
        turns: m['turns'].to_i, orders: (d['orders'] || {})[h].to_a.last(30).reverse,
        log: Array(m['log']).last(12).map { |x| { who: x['w'] == 'u' ? 'me' : 'scout', text: x['t'] } } }
    end
  end
  route(server, '/api/scout/forget') do |b, h|
    store do |d|
      m = (d['scout_mem'] || {})[h]
      case b['what']
      when 'note' then m && m['notes'].delete_at(b['i'].to_i) if b['i'].to_i.between?(0, 99)
      when 'chat' then m && m['log'].clear
      when 'all' then scout_forget!(d, h)
      else raise 'Forget what?'
      end
      { ok: true }
    end
  end
  # "What did you get, and how was it?": a place, the dish, 1-5 stars, a short note
  route(server, '/api/rate') do |b, h|
    limit!("rate:#{h}", 60, 3600)
    id = b['id'].to_s[0, 30]
    p = Places.find(id) or raise 'No such place.'
    s = b['stars'].to_i
    raise 'Pick 1 to 5 stars.' unless s.between?(1, 5)
    dish = b['dish'].to_s.gsub(/\s+/, ' ').strip[0, 80]
    note = b['note'].to_s.gsub(/\s+/, ' ').strip[0, 200]
    # only the average stars are shown to others; the dish and note are theirs (and Scout's)
    store do |d|
      ((d['ratings'] ||= {})[id] ||= {})[h] = { 's' => s, 'dish' => dish.empty? ? nil : dish, 'note' => note.empty? ? nil : note, 'at' => now_ms }.compact
      list = ((d['orders'] ||= {})[h] ||= [])
      list << { 'id' => id, 'name' => p['name'], 'dish' => dish.empty? ? nil : dish, 's' => s, 'note' => note.empty? ? nil : note, 'at' => now_ms }.compact
      list.shift while list.size > 200
      remember_taste!(d, h, 'checkin', 'place', id) if s >= 4   # loved it: Scout leans that way
      { ok: true, rating: place_rating(d, id) }
    end
  end
  route(server, '/api/rating', auth: false, get: true) do |_b, _h, req|
    id = req.query['id'].to_s[0, 30]
    store(write: false) { |d| { rating: place_rating(d, id) } }
  end
end
