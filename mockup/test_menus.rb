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
  <a href="https://evil.example.com/menu">menu elsewhere</a> <a href="/files/dinner.pdf">Dinner menu (PDF)</a>
  <a href="mailto:a@b.c">menu by mail</a></nav>
  <h2>Tacos</h2><ul><li>Al pastor &amp; pineapple <b>$4.50</b></li><li>Barbacoa $5</li></ul>
  <script type="application/ld+json">{"@type":"Menu","name":"Main"}</script></body></html>
H
links = menu_links(html, 'https://www.tacos.example/home')
check('menu links: same site and menu hosts, PDFs first', links == ['https://www.tacos.example/files/dinner.pdf', 'https://www.tacos.example/menu', 'https://order.toasttab.com/online/x'], links.inspect)
t = menu_text(html.dup, 'text/html')
check('page text keeps the menu, drops scripts', t.include?("Al pastor & pineapple $4.50") && t.include?('Barbacoa $5') && !t.include?('var a'), t)
check('page text keeps JSON-LD menus', t.include?('"@type":"Menu"'))

m = menu_clean({ 'sections' => [{ 'name' => 'Tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4.50', 'desc' => '' }, { 'name' => ' ' }] },
                                { 'name' => 'Empty', 'items' => [] }],
                 'sources' => ['https://tacos.example/menu', 'javascript:alert(1)', 'https://tacos.example/menu'], 'note' => 'n' }, 'site')
check('clean: empty items and sections dropped', m['sections'] == [{ 'name' => 'Tacos', 'items' => [{ 'name' => 'Al pastor', 'price' => '$4.50' }] }], m.inspect)
check('clean: only web sources, once', m['sources'] == ['https://tacos.example/menu'], m['sources'].inspect)
check('count', menu_count(m) == 1)

Dir.mktmpdir do |d|
  Object.send(:remove_const, :MENU_DIR); Object.const_set(:MENU_DIR, d)
  File.write(menu_file('n1'), JSON.generate(m.merge('at' => Time.now.to_i - 3 * 86_400)))
  check('cache: a found menu keeps for 14 days', menu_cached('n1'))
  File.write(menu_file('n2'), JSON.generate(m.merge('sections' => [], 'at' => Time.now.to_i - 3 * 86_400)))
  check('cache: a miss is retried after 2 days', menu_cached('n2').nil?)
  check('cache file names are safe', menu_file('../../etc/x') == File.join(d, 'etcx.json'))
end
puts "\n#{$pass}/#{$pass + $fail} passed"
exit($fail.zero? ? 0 : 1)
