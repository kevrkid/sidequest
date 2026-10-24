# menus.rb on its own: the page fetcher refuses addresses inside the network, menu links and text come out of HTML,
# and Claude's answer is trimmed to the shape the app shows. No network or Claude needed.  ruby test_menus.rb
require 'json'
require 'net/http'
require 'open3'
require 'tmpdir'
require 'fileutils'
class RateLimited < StandardError; end
require_relative 'menus'

$pass = $fail = 0
def check(name, ok, extra = '')
  ok ? $pass += 1 : $fail += 1
  puts "#{ok ? 'PASS' : 'FAIL'} #{name}#{ok ? '' : " #{extra}"}"
end
def refused(url)
  menu_get(url)
  false
rescue => e
  e.message
end

%w[http://127.0.0.1/ http://localhost:8798/api/health http://10.0.0.5/ http://192.168.1.1/ http://169.254.169.254/latest/meta-data
   http://[::1]/ file:///etc/passwd ftp://example.com/ http://example.com:8080/].each do |u|
  r = refused(u)
  check("refuses #{u}", r.is_a?(String), r.inspect)
end

html = <<~H
  <html><head><title>x</title><script>var a="$1.00 $2.00 $3.00"</script></head><body>
  <nav><a href="/menu">Our Menu</a> <a href="/about">About</a> <a href="https://order.toasttab.com/online/x">Order</a>
  <a href="https://evil.example.com/menu">menu elsewhere</a> <a href="/files/dinner.pdf">Dinner menu (PDF)</a> <a href="https://cdn.files.example/x/Clarks_Lunch%2010.23.26.pdf">Lunch</a>
  <a href="https://cdn.files.example/x/press-kit.pdf">Press</a>
  <a href="mailto:a@b.c">menu by mail</a></nav>
  <h2>Tacos</h2><ul><li>Al pastor &amp; pineapple <b>$4.50</b></li><li>Barbacoa $5</li></ul>
  <script type="application/ld+json">{"@type":"Menu","name":"Main"}</script></body></html>
H
links = menu_links(html, 'https://www.tacos.example/home')
check('menu links: same site, menu PDFs anywhere, menu hosts; PDFs first', links == ['https://www.tacos.example/files/dinner.pdf', 'https://cdn.files.example/x/Clarks_Lunch%2010.23.26.pdf', 'https://www.tacos.example/menu', 'https://order.toasttab.com/online/x'], links.inspect)
t = menu_text(html.dup, 'text/html')
check('page text keeps the menu, drops scripts', t.include?("Al pastor & pineapple $4.50") && t.include?('Barbacoa $5') && !t.include?('var a'), t)
check('page text keeps JSON-LD menus', t.include?('"@type":"Menu"'))

im = menu_imgs('<img src="/logo-menu.png" alt="logo"><img data-image="https://cdn.example/dinner+10.5.26.png" src="x.png" alt="">' \
               '<img src="/food/tacos.jpg" alt="Our tacos"><img src="data:image/gif;base64,R0" alt="menu"><img src="/m/drinks.jpg?w=1">', 'https://tacos.example/menu')
check('menu pictures on the page: menus only, no logos or food shots', im == ['https://cdn.example/dinner+10.5.26.png', 'https://tacos.example/m/drinks.jpg?w=1'], im.inspect)

check('prices: $ and bare numbers at line ends', menu_prices("Bibb Salad        15\nWedge Salad   18\n*add Shrimp     +12\nTacos $4.50\nOpen 11 to 10\nCall 512 555 1234") == 4,
      menu_prices("Bibb Salad        15\nWedge Salad   18\n*add Shrimp     +12\nTacos $4.50\nOpen 11 to 10\nCall 512 555 1234"))

m = menu_clean({ 'sections' => [{ 'name' => 'Tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4.50', 'desc' => '' }, { 'name' => ' ' }] },
                                { 'name' => 'Empty', 'items' => [] }],
                 'sources' => ['https://tacos.example/menu', 'javascript:alert(1)', 'https://tacos.example/menu'], 'note' => 'n' }, 'site')
check('clean: empty items and sections dropped', m['sections'] == [{ 'name' => 'Tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4.50' }] }], m.inspect)
check('clean: only web sources, once', m['sources'] == ['https://tacos.example/menu'], m['sources'].inspect)
check('count', menu_count(m) == 1)

shot = menu_clean({ 'sections' => [{ 'name' => 'Drinks', 'items' => [{ 'name' => 'Margarita', 'price' => '$12' }] }],
                    'note' => 'Only the drinks menu was in the photos' }, 'photos').merge('sources' => ['https://maps.google.com/?cid=1'])
web = menu_clean({ 'sections' => [{ 'name' => 'drinks', 'items' => [{ 'name' => 'margarita', 'price' => '$14' }, { 'name' => 'Paloma', 'price' => '$11' }] },
                                  { 'name' => 'Food', 'items' => [{ 'name' => 'Oysters', 'price' => 'MP' }] }],
                   'sources' => ['https://ubereats.com/x'] }, 'web')
mm = menu_merge(shot, web)
check('merge: photos first, web adds missing items and sections', mm['sections'].map { |s| [s['name'], s['items'].map { |i| i['name'] }] } ==
      [['Drinks', %w[Margarita Paloma]], ['Food', ['Oysters']]], mm['sections'].inspect)
check('merge: photo price kept, both sources, says both', mm['sections'][0]['items'][0]['price'] == '$12' && mm['sources'].size == 2 && mm['from'] == 'photos+web')
check('merge: web found nothing = photos only', menu_merge(shot, menu_clean({}, 'web'))['from'] == 'photos')

# parallel parts: cut between lines, joined in order with a section that runs on merged and repeats dropped
pp = menu_parts("a\n" * 3000, 1000)
check('parts: cut between lines, nothing lost', pp.all? { |x| x.size <= 1000 } && pp.join == "a\n" * 3000, pp.map(&:size).inspect)
p1 = menu_clean({ 'sections' => [{ 'name' => 'Tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4' }] }], 'sources' => ['https://t.example/m'] }, 'site')
p2 = menu_clean({ 'sections' => [{ 'name' => 'tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4' }, { 'name' => 'Barbacoa', 'price' => '$5' }] },
                                 { 'name' => 'Drinks', 'items' => [{ 'name' => 'Agua fresca', 'price' => '$3' }] }], 'sources' => ['https://t.example/m'] }, 'site')
jj = menu_join([p1, nil, p2], 'site')
check('join: running section merged, repeat dropped, gaps skipped', jj['sections'].map { |x| [x['name'], x['items'].map { |i| i['name'] }] } ==
      [['Tacos', ['Al pastor', 'Barbacoa']], ['Drinks', ['Agua fresca']]] && jj['sources'] == ['https://t.example/m'], jj['sections'].inspect)
dd = menu_dedupe([['a', "Home\nTacos $4\nOpen 11-10\n"], ['b', "Tacos $4\nBarbacoa $5\nOpen 11-10\n"]])
check('dedupe: lines from an earlier page dropped', dd[1][1] == "Barbacoa $5\n", dd.inspect)

Dir.mktmpdir do |d|
  Object.send(:remove_const, :MENU_DIR); Object.const_set(:MENU_DIR, d)
  File.write(menu_file('n1'), JSON.generate(m.merge('at' => Time.now.to_i - 3 * 86_400)))
  check('cache: a found menu keeps for 14 days', menu_cached('n1'))
  File.write(menu_file('n2'), JSON.generate(m.merge('sections' => [], 'at' => Time.now.to_i - 3 * 86_400)))
  check('cache: a miss is retried after 2 days', menu_cached('n2').nil?)
  File.write(menu_file('n3'), JSON.generate(m.merge('at' => Time.now.to_i - 20 * 86_400)))
  check('cache: an old menu only when asked for (shown while a new read runs)', menu_cached('n3').nil? && menu_cached('n3', stale: true)['stale'] == true)
  check('cache file names are safe', menu_file('../../etc/x') == File.join(d, 'etcx.json'))
end
puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
