# Web Push with nothing but Ruby's OpenSSL: message encryption (RFC 8291, aes128gcm) and VAPID sign-in (RFC 8292),
# so notifications reach phones even when Side Quest is closed. No push company account is needed; the browser's own
# push service (Google, Apple, Mozilla, Microsoft) delivers it. test_webpush.rb checks this against the RFC's example.
require 'openssl'
require 'json'
require 'net/http'
require 'uri'
require 'securerandom'

module WebPush
  module_function

  CURVE = 'prime256v1'
  # Only real push services: the address comes from the browser, so never let it point anywhere else (SSRF).
  HOSTS = /\A(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|push\.services\.mozilla\.com|
             [a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)\z/x

  def b64u(s) [s].pack('m0').tr('+/', '-_').delete('=') end
  def unb64u(s) t = s.to_s.tr('-_', '+/'); (t + '=' * ((4 - t.size % 4) % 4)).unpack1('m') end
  def hmac(k, d) OpenSSL::HMAC.digest('SHA256', k, d) end
  def hkdf(salt, ikm, info, len) hmac(hmac(salt, ikm), info + "\x01".b)[0, len] end   # one block is enough here (len <= 32)

  def group() @group ||= OpenSSL::PKey::EC::Group.new(CURVE) end
  def point(raw) OpenSSL::PKey::EC::Point.new(group, OpenSSL::BN.new(raw, 2)) end
  def pub_raw(key) key.public_key.to_bn(:uncompressed).to_s(2) end

  def key_from_private(raw)
    k = OpenSSL::PKey::EC.new(CURVE)
    k.private_key = OpenSSL::BN.new(raw, 2)
    k.public_key = group.generator.mul(k.private_key)
    k
  end

  def new_key
    k = OpenSSL::PKey::EC.new(CURVE)
    k.generate_key
    k
  end

  # RFC 8291: one record, aes128gcm. as_key/salt are only passed in by the test.
  def encrypt(plaintext, ua_public, auth, as_key: new_key, salt: SecureRandom.random_bytes(16))
    as_pub = pub_raw(as_key)
    shared = as_key.dh_compute_key(point(ua_public))
    ikm = hkdf(auth, shared, "WebPush: info\x00".b + ua_public + as_pub, 32)
    cek = hkdf(salt, ikm, "Content-Encoding: aes128gcm\x00".b, 16)
    nonce = hkdf(salt, ikm, "Content-Encoding: nonce\x00".b, 12)
    body = aes128gcm(cek, nonce, plaintext.b + "\x02".b)
    salt + [4096].pack('N') + [as_pub.bytesize].pack('C') + as_pub + body
  end

  # AES-128-GCM, ciphertext + 16-byte tag. OpenSSL's when it works; macOS's system Ruby is built on LibreSSL, whose
  # GCM is broken through Ruby's bindings, so there it's done by hand from AES-ECB (same output; the test checks it).
  def aes128gcm(key, iv, data)
    c = OpenSSL::Cipher.new('aes-128-gcm').encrypt
    c.key = key; c.iv = iv
    c.update(data) + c.final + c.auth_tag
  rescue OpenSSL::Cipher::CipherError
    gcm_by_hand(key, iv, data)
  end

  def gcm_by_hand(key, iv, data)
    ecb = OpenSSL::Cipher.new('aes-128-ecb').encrypt
    ecb.key = key; ecb.padding = 0
    aes = ->(block) { ecb.update(block) }
    h = aes.("\x00".b * 16).unpack1('H*').to_i(16)
    j0 = iv + [1].pack('N')
    out = ''.b
    data.bytes.each_slice(16).with_index do |chunk, i|
      ks = aes.(iv + [2 + i].pack('N')).bytes
      out << chunk.each_with_index.map { |b, k| b ^ ks[k] }.pack('C*')
    end
    tag = ghash(h, out) ^ aes.(j0).unpack1('H*').to_i(16)
    out + [tag.to_s(16).rjust(32, '0')].pack('H*')
  end

  R = 0xE1 << 120
  def gmul(x, y)
    z = 0; v = y
    127.downto(0) { |i| z ^= v if x[i] == 1; v = v[0] == 1 ? (v >> 1) ^ R : v >> 1 }
    z
  end

  def ghash(h, c)   # no additional data
    y = 0
    padded = c + "\x00".b * ((16 - c.bytesize % 16) % 16)
    padded.unpack('H32' * (padded.bytesize / 16)).each { |blk| y = gmul(y ^ blk.to_i(16), h) }
    gmul(y ^ (c.bytesize * 8), h)   # lengths block: 64-bit len(A)=0, 64-bit len(C) in bits
  end

  # VAPID (RFC 8292): a short ES256 token saying which server is sending, for the push service at `aud`.
  def vapid_jwt(aud, key, subject)
    seg = ->(h) { b64u(JSON.generate(h)) }
    input = "#{seg.(typ: 'JWT', alg: 'ES256')}.#{seg.(aud: aud, exp: Time.now.to_i + 12 * 3600, sub: subject)}"
    der = key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(input))
    rs = OpenSSL::ASN1.decode(der).value.map { |i| i.value.to_s(2).rjust(32, "\x00".b)[-32, 32] }.join
    "#{input}.#{b64u(rs)}"
  end

  TEST_HOST = ENV['SQ_PUSH_TEST_HOST'].to_s   # tests only: a fake push service on this host (plain http allowed)
  def valid_sub?(sub)
    return false unless sub.is_a?(Hash) && sub['keys'].is_a?(Hash)
    u = URI(sub['endpoint'].to_s) rescue nil
    test = !TEST_HOST.empty? && u.is_a?(URI::HTTP) && "#{u.host}:#{u.port}" == TEST_HOST
    (test || (u.is_a?(URI::HTTPS) && u.host.to_s =~ HOSTS)) && unb64u(sub['keys']['p256dh']).bytesize == 65 && unb64u(sub['keys']['auth']).bytesize == 16
  rescue ArgumentError
    false
  end

  # Returns :ok, :gone (subscription expired: delete it) or :failed.
  def deliver(sub, payload, key, subject, ttl: 86_400)
    return :gone unless valid_sub?(sub)
    u = URI(sub['endpoint'])
    body = encrypt(JSON.generate(payload), unb64u(sub['keys']['p256dh']), unb64u(sub['keys']['auth']))
    req = Net::HTTP::Post.new(u.request_uri, 'TTL' => ttl.to_s, 'Content-Encoding' => 'aes128gcm', 'Content-Type' => 'application/octet-stream',
                              'Urgency' => 'normal',
                              'Authorization' => "vapid t=#{vapid_jwt("#{u.scheme}://#{u.host}", key, subject)}, k=#{b64u(pub_raw(key))}")
    req.body = body
    res = Net::HTTP.start(u.host, u.port, use_ssl: u.scheme == 'https', open_timeout: 5, read_timeout: 10) { |h| h.request(req) }
    code = res.code.to_i
    code.between?(200, 299) ? :ok : [404, 410].include?(code) ? :gone : (warn("[push] #{u.host} said #{code}: #{res.body.to_s[0, 120]}"); :failed)
  rescue StandardError => e
    warn "[push] #{e.class}: #{e.message[0, 120]}"
    :failed
  end
end
