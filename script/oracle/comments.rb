# Runs the public comment workflow (preview, then submit with the one-time
# nonce) against the Textpattern oracle and this Rails port and compares
# every step. Random nonces/secrets are masked before comparing.
#
#   ruby script/oracle/comments.rb [/articles/hello-world]
require "net/http"
require "uri"
require "fileutils"
require "cgi"

ORACLE = ENV.fetch("ORACLE_URL", "http://localhost:8081")
RAILS = ENV.fetch("RAILS_URL", "http://127.0.0.1:3001")
OUT = File.expand_path("../../tmp/oracle/diffs", __dir__)
FileUtils.mkdir_p(OUT)
Dir[File.join(OUT, "comment_*")].each { |f| File.delete(f) }
ARTICLE = ARGV[0] || "/articles/hello-world"

def request(base, path, form = nil, cookies = {})
  uri = URI.join(base, path)
  req = form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req.set_form_data(form) if form
  req["Cookie"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") if cookies.any?
  res = Net::HTTP.start(uri.host, uri.port) { |http| http.request(req) }
  Array(res.get_fields("set-cookie")).each do |c|
    name, value = c.split(";").first.split("=", 2)
    cookies[name] = value
  end
  res
end

# The preview form carries a hidden nonce input (random name and value) and a
# message textarea named md5("message" . secret).
def secrets(html)
  nonce = html.scan(/<input name="([0-9a-f]{1,31})" type="hidden" value="([0-9a-f]+)">/).find { |n, v| (n + v).length == 32 }
  message = html[/<textarea[^>]*name="([0-9a-f]{32})"/, 1]
  [ nonce, message ]
end

# Comments posted during the run show the current time; both servers post
# them milliseconds apart, which can straddle a minute.
TODAY = Time.now.utc.strftime("%Y-%m-%d")

def norm(html, base)
  authority = base.sub(%r{\Ahttps?://}, "")
  html.to_s.dup.force_encoding("UTF-8").gsub(base, "HOST").gsub(authority, "HOST")
      .gsub(/#{TODAY} \d{2}:\d{2}/, "#{TODAY} HH:MM")
      .gsub(/<input name="[0-9a-f]{1,31}" type="hidden" value="[0-9a-f]+">/, '<input name="NONCE" type="hidden" value="NONCE">')
      .gsub(/name="[0-9a-f]{32}"/, 'name="MESSAGE"')
      .gsub(/^(Runtime|Query time) *: [\d.]+ ms$/, "\\1: N ms").gsub(/^Queries( *): \d+$/, "Queries\\1: N")
      .gsub(/^Memory \(\*\): \d+ kB$/, "Memory (*): N kB")
end

def compare(step, a, b)
  if a == b
    puts "SAME  #{step}"
    true
  else
    name = "comment_#{step.gsub(/\W+/, '_')}"
    File.write(File.join(OUT, "#{name}.php.html"), a)
    File.write(File.join(OUT, "#{name}.rb.html"), b)
    diff = `diff #{File.join(OUT, "#{name}.php.html")} #{File.join(OUT, "#{name}.rb.html")} | head -c 20000`
    File.write(File.join(OUT, "#{name}.diff"), diff)
    puts "DIFF  #{step} (#{diff.lines.count { |l| l.start_with?('<') }} lines differ)"
    false
  end
end

fields = { "name" => "Carla", "email" => "carla@example.com", "web" => "carla.example.com",
           "message" => "Nice *post*, thanks!", "parentid" => "1", "backpage" => ARTICLE }
results = [ ORACLE, RAILS ].map do |base|
  cookies = {}
  steps = {}
  preview = request(base, ARTICLE, fields.merge("preview" => "Preview"), cookies)
  steps["preview"] = "#{preview.code}\n#{norm(preview.body, base)}"
  nonce, message = secrets(preview.body.to_s)
  submit_form = fields.merge("submit" => "Submit")
  if nonce && message
    submit_form[nonce[0]] = nonce[1]
    submit_form[message] = fields["message"]
  end
  submit = request(base, ARTICLE, submit_form, cookies)
  location = submit["location"].to_s
  steps["submit"] = "#{submit.code}\n#{norm(location, base)}\n#{norm(submit.body, base)}"
  after = location.empty? ? submit : request(base, location.sub(base, ""), nil, cookies)
  steps["after"] = "#{after.code}\n#{norm(after.body, base)}"
  replay = request(base, ARTICLE, submit_form, cookies)
  steps["replay"] = "#{replay.code}\n#{norm(replay["location"], base)}\n#{norm(replay.body, base)}"
  steps
end

ok = results[0].keys.count { |step| compare(step, results[0][step], results[1][step]) }
puts "#{ok}/#{results[0].size} identical"
