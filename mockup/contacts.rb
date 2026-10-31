# Find friends by email or phone number. You link your own email and phone (You → Privacy) and choose whether people
# can find you by them (off until you turn it on). Neither is ever shown to anyone: the server keeps only a keyed hash
# of each (data/contact_key, made once, never leaves the server) plus a masked copy for your own screen
# ("k•••@gmail.com", "•••-•••-1234"). Finding someone takes the exact email or number: /api/contact/match gets a list
# (typed, or picked from the phone's contacts) and answers only with the handles of people who said yes. Nothing is
# verified yet (no email / text service), so a match means "this person typed that address", not proof.
CONTACT_KEY_FILE = File.join(__dir__, 'data', 'contact_key')
CONTACT_MATCH_MAX = 1000   # contacts per request (a whole exported address book)
CONTACT_MATCH_PER_HOUR = 10

def contact_key
  @contact_key ||= begin
    unless File.exist?(CONTACT_KEY_FILE)
      File.write(CONTACT_KEY_FILE, SecureRandom.hex(32))
      File.chmod(0o600, CONTACT_KEY_FILE)
    end
    File.read(CONTACT_KEY_FILE).strip
  end
end

def contact_email(s)
  e = s.to_s.strip.downcase
  e =~ /\A[^@\s]{1,64}@[^@\s]+\.[a-z]{2,}\z/ && e.size <= 254 ? e : nil
end

def contact_phone(s)   # US numbers as 1 + 10 digits; others as typed, 8-15 digits (with their country code)
  d = s.to_s.gsub(/\D/, '')
  d = "1#{d}" if d.size == 10
  d.size.between?(8, 15) ? d : nil
end

def contact_hash(kind, v)
  OpenSSL::HMAC.hexdigest('SHA256', contact_key, "#{kind}:#{v}")
end

def contact_mask_email(e)
  name, dom = e.split('@', 2)
  "#{name[0]}•••@#{dom}"
end

def contact_mask_phone(p)
  "•••-•••-#{p[-4..-1]}"
end

def contact_view(u)   # what you see about your own linked contacts
  c = u['contact'] || {}
  { email: c['email_m'], phone: c['phone_m'], find: !!c['find'] }
end

def mount_contacts(server)
  route(server, '/api/contact', get: true) { |_b, h| store(write: false) { |d| contact_view(d['users'][h]) } }

  # Link or change your email / phone (an empty value unlinks it), and turn "find me by these" on or off.
  route(server, '/api/contact/set') do |b, h|
    limit!("contact:#{h}", 30, 3600)
    em = b.key?('email') && b['email'].to_s.strip != '' ? (contact_email(b['email']) or raise 'That email address doesn\'t look right.') : nil
    ph = b.key?('phone') && b['phone'].to_s.strip != '' ? (contact_phone(b['phone']) or raise 'Type the phone number with its area code.') : nil
    store do |d|
      c = (d['users'][h]['contact'] ||= {})
      if b.key?('email')
        em ? c.merge!('email_h' => contact_hash('e', em), 'email_m' => contact_mask_email(em)) : c.delete_if { |k, _| k.start_with?('email') }
      end
      if b.key?('phone')
        ph ? c.merge!('phone_h' => contact_hash('p', ph), 'phone_m' => contact_mask_phone(ph)) : c.delete_if { |k, _| k.start_with?('phone') }
      end
      c['find'] = b['find'] == true if b.key?('find')
      d['users'][h].delete('contact') if c.reject { |k, _| k == 'find' }.empty? && !c['find']
      contact_view(d['users'][h])
    end
  end

  # Which of these contacts are on Side Quest (and let people find them)? Answers with handles and the position of the
  # contact that matched, so the phone can show the contact's name; never says which addresses weren't found.
  route(server, '/api/contact/match') do |b, h|
    limit!("contact-match:#{h}", CONTACT_MATCH_PER_HOUR, 3600)
    list = Array(b['contacts']).first(CONTACT_MATCH_MAX)
    want = {}   # hash => [positions]
    list.each_with_index do |x, i|
      Array(x.is_a?(Hash) ? x['emails'] : nil).first(5).map { |e| contact_email(e) }.compact.each { |e| (want[contact_hash('e', e)] ||= []) << i }
      Array(x.is_a?(Hash) ? x['phones'] : nil).first(5).map { |p| contact_phone(p) }.compact.each { |p| (want[contact_hash('p', p)] ||= []) << i }
    end
    store(write: false) do |d|
      hidden = blocked_between(d, h)
      found = {}
      d['users'].each_value do |u|
        c = u['contact']
        next unless c && c['find'] && u['h'] != h && !u['banned'] && !hidden.include?(u['h'])
        idx = [c['email_h'], c['phone_h']].compact.flat_map { |k| want[k] || [] }
        found[u['h']] = idx.uniq if idx.any?
      end
      { found: found.map { |who, idx| { h: who, i: idx, friend: (d['friends'][h] || []).include?(who) } } }
    end
  end
end
