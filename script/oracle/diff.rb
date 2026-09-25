# Fetches the same URLs from the real Textpattern (oracle) and from this Rails
# port, normalises host names and whitespace and writes a diff per URL.
#
#   ruby script/oracle/diff.rb            # default URL set
#   ruby script/oracle/diff.rb /about/ /?q=ruby
#
# ORACLE_URL (default http://localhost:8081) and RAILS_URL
# (default http://127.0.0.1:3001) select the two servers.
require "net/http"
require "uri"
require "fileutils"

ORACLE = ENV.fetch("ORACLE_URL", "http://localhost:8081")
RAILS = ENV.fetch("RAILS_URL", "http://127.0.0.1:3001")
OUT = File.expand_path("../../tmp/oracle/diffs", __dir__)
FileUtils.rm_rf(OUT)
FileUtils.mkdir_p(OUT)

DEFAULT_PATHS = %w[
  / /?pg=2 /articles/ /articles/?pg=2 /articles/hello-world /articles/ruby-tips /articles/rails-guide
  /news/php-notes /about/ /about/about-this-site /category/ruby/ /category/tech/ /author/Maria+Silva/
  /?q=ruby /?q=zzzz /?q=ruby&pg=2 /nothing/here /articles/nothing /rss/ /atom/ /?rss=1&section=news
  /?atom=1&category=ruby /?rss=1&area=link /?c=tech /?c=nope /news/ /?s=news&pg=2 /?id=2 /?month=2025-05
  /file_download/1 /?author=admin /?f=app.js /?f=extra.js,app.js /news/?f=app.js
].freeze
# --crawl[=N]: also follow the oracle's same-site links (up to N pages).
# --skip=REGEX: leave out matching paths (and do not crawl them).
crawl = ARGV.find { |a| a.start_with?("--crawl") }
CRAWL_LIMIT = crawl ? (crawl[/=(\d+)/, 1] || 200).to_i : 0
skip = ARGV.find { |a| a.start_with?("--skip=") }
SKIP = skip ? Regexp.new(skip.delete_prefix("--skip=")) : nil
args = ARGV.reject { |a| a.start_with?("--") }
PATHS = args.empty? ? DEFAULT_PATHS.dup : args

# STRICT=1 compares bytes (only host names and trace timings are masked)
# plus the caching/type headers instead of whitespace-normalised bodies.
STRICT = ENV["STRICT"] == "1"
HEADERS = %w[content-type location last-modified etag cache-control vary im www-authenticate].freeze

def fetch(base, path)
  res = Net::HTTP.get_response(URI.join(base, path))
  body = res.body.to_s.dup.force_encoding("UTF-8")
  head = HEADERS.filter_map { |h| "#{h}: #{res[h]}" if res[h] }
  head = res["location"] ? [ "location: #{res['location']}" ] : [] unless STRICT
  body = "#{head.join("\n")}\n\n#{body}" if head.any?
  [ res.code, body ]
rescue StandardError => e
  [ "ERR", e.message ]
end

def norm(body, base)
  authority = base.sub(%r{\Ahttps?://}, "")
  # debug mode: PHP/Ruby backtraces and the full trace log cannot match.
  body = body.gsub(%r{\n?<pre class="backtrace" dir="ltr"><code>.*?</code></pre>}m, "")
             .gsub(/\n<!-- (?:Trace|Query) log:.*?-->\n/m, "")
  # Apache's mod_deflate (not Textpattern) adds these.
  body = body.sub(/^etag: "(.*)-gzip"$/, 'etag: "\\1"').sub(/^vary: Accept-Encoding\n/, "").sub(/^(vary: .*), ?Accept-Encoding$/, '\\1')
             .sub(/^vary: .*$/) { |v| v.gsub(/,\s*/, ", ") }
  body = body.gsub(base, "HOST").gsub(authority, "HOST")
  body = body.gsub(/[ \t]+/, " ").gsub(/\s*\n\s*/, "\n").strip unless STRICT
  body.gsub(/^(Runtime|Query time) *: [\d.]+ ms$/, "\\1: N ms").gsub(/^Queries( *): \d+$/, "Queries\\1: N")
      .gsub(/^Memory \(\*\): \d+ kB$/, "Memory (*): N kB")
      .gsub(%r{/var/www/html/|#{Regexp.escape(File.expand_path("../..", __dir__))}/}, "ROOT/")
end

def links(html, base)
  html.scan(/(?:href|action)="([^"#]*)/).flatten.filter_map do |href|
    href = CGI.unescapeHTML(href)
    next unless href.start_with?(base) || (href.start_with?("/") && !href.start_with?("//"))

    path = href.delete_prefix(base)
    path = "/#{path}" unless path.start_with?("/")
    # Static directories are the web server's business, not Textpattern's.
    path unless path.start_with?("/textpattern", "/css.php", "/images/", "/files/", "/themes/") || path.match?(/[?&](rss|atom)=|\/(rss|atom)\/?\z/)
  end
end

require "cgi"
ok = 0
seen = {}
queue = PATHS.dup
total = 0
while (path = queue.shift)
  next if seen[path] || (SKIP && path.match?(SKIP))

  seen[path] = true
  total += 1
  c1, php = fetch(ORACLE, path)
  if total < CRAWL_LIMIT
    links(php, ORACLE).each { |l| queue << l unless seen[l] || queue.include?(l) || seen.size + queue.size >= CRAWL_LIMIT }
  end
  c2, rb = fetch(RAILS, path)
  a = norm(php, ORACLE)
  b = norm(rb, RAILS)
  if a == b && c1 == c2
    ok += 1
    puts "SAME  #{c1} #{path}"
  else
    name = path.gsub(/[^a-z0-9]+/i, "_")
    php_file = File.join(OUT, "#{name}.php.html")
    rb_file = File.join(OUT, "#{name}.rb.html")
    File.write(php_file, "#{a}\n")
    File.write(rb_file, "#{b}\n")
    diff = `diff #{php_file} #{rb_file} | head -c 20000`
    File.write(File.join(OUT, "#{name}.diff"), diff)
    puts "DIFF  #{c1}/#{c2} #{path} (#{diff.lines.count { |l| l.start_with?('<') }} lines differ)"
  end
end
puts "#{ok}/#{total} identical (diffs in #{OUT})"
