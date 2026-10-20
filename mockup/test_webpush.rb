# Web Push encryption and VAPID against RFC 8291 Appendix A / RFC 8292: ruby test_webpush.rb
require_relative 'webpush'
W = WebPush

$pass = $fail = 0
def t(name)
  yield ? ($pass += 1; puts "PASS #{name}") : ($fail += 1; puts "FAIL #{name}")
rescue => e
  $fail += 1; puts "FAIL #{name}: #{e.class} #{e.message}"
end

plain = W.unb64u('V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0byBiZSBhIHdhdGVybWVsb24')
as_key = W.key_from_private(W.unb64u('yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw'))
ua_pub = W.unb64u('BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4')
auth = W.unb64u('BTBZMqHH6r4Tts7J_aSIgg')
salt = W.unb64u('DGv6ra1nlYgDCS1FRnbzlw')

t('application server public key from its private key') {
  W.b64u(W.pub_raw(as_key)) == 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8'
}
t('ECDH shared secret matches the RFC') {
  W.b64u(as_key.dh_compute_key(W.point(ua_pub))) == 'kyrL1jIIOHEzg3sM2ZWRHDRB62YACZhhSlknJ672kSs'
}
msg = W.encrypt(plain, ua_pub, auth, as_key: as_key, salt: salt)
t('header (salt, record size, key) matches the RFC') {
  W.b64u(msg[0, 86]) == 'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8'
}
t('encrypted body matches the RFC byte for byte') {
  W.b64u(msg[86..-1]) == '8pfeW0KbunFT06SuDKoJH9Ql87S1QUrdirN6GcG7sFz1y1sqLgVi1VhjVkHsUoEsbI_0LpXMuGvnzQ'
}
t('VAPID token verifies with the public key (ES256, raw r||s)') {
  k = W.new_key
  jwt = W.vapid_jwt('https://fcm.googleapis.com', k, 'mailto:test@example.com')
  h, c, sig = jwt.split('.')
  rs = W.unb64u(sig)
  der = OpenSSL::ASN1::Sequence([OpenSSL::ASN1::Integer(OpenSSL::BN.new(rs[0, 32], 2)), OpenSSL::ASN1::Integer(OpenSSL::BN.new(rs[32, 32], 2))]).to_der
  claims = JSON.parse(W.unb64u(c))
  rs.bytesize == 64 && k.dsa_verify_asn1(OpenSSL::Digest::SHA256.digest("#{h}.#{c}"), der) && claims['aud'] == 'https://fcm.googleapis.com' && claims['exp'] > Time.now.to_i
}
t('only real push services are accepted as addresses (no SSRF)') {
  good = { 'endpoint' => 'https://fcm.googleapis.com/fcm/send/abc', 'keys' => { 'p256dh' => W.b64u(ua_pub), 'auth' => W.b64u(auth) } }
  bad = [good.merge('endpoint' => 'https://127.0.0.1/x'), good.merge('endpoint' => 'http://fcm.googleapis.com/x'),
         good.merge('endpoint' => 'https://fcm.googleapis.com.evil.com/x'), good.merge('keys' => { 'p256dh' => 'x', 'auth' => 'y' })]
  W.valid_sub?(good) && bad.none? { |s| W.valid_sub?(s) } &&
    W.valid_sub?(good.merge('endpoint' => 'https://web.push.apple.com/QGx')) && W.valid_sub?(good.merge('endpoint' => 'https://updates.push.services.mozilla.com/wpush/v2/x'))
}
puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
