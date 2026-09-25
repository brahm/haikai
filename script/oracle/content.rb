# Builds deterministic comparison content in the current Rails database and
# writes a MySQL script with the same rows for the Textpattern oracle.
# Usage: DATABASE_URL=sqlite3:... bin/rails runner content.rb OUT.sql
out_path = ARGV[0] || "compare.sql"

TABLES = %w[textpattern txp_category txp_section txp_page txp_form txp_css txp_skin txp_link txp_image txp_discuss txp_file].freeze
conn = ActiveRecord::Base.connection
TABLES.each { |t| conn.execute("DELETE FROM #{t}") }
Pref.delete_all
User.delete_all
Txp::DefaultPrefs.install!("language" => "en", "language_ui" => "en")

prefs = {
  "sitename" => "Compare site", "site_slogan" => "Same & different", "permlink_mode" => "section_title",
  "production_status" => "live", "timezone_key" => "UTC", "dateformat" => "%Y-%m-%d %H:%M",
  "archive_dateformat" => "%d %b %Y", "comments_dateformat" => "%Y-%m-%d", "use_comments" => "1",
  "comments_disabled_after" => "0", "comments_moderate" => "0", "custom_1_set" => "color", "custom_2_set" => "size",
  "doctype" => "html5", "enable_short_tags" => "1", "rss_how_many" => "5", "comments_default_invite" => "Comment",
  "articles_use_excerpts" => "1", "use_textile" => "1", "attach_titles_to_permalinks" => "1", "trailing_slash" => "0",
  "logging" => "none", "publish_expired_articles" => "0", "comments_are_ol" => "1", "never_display_email" => "1",
  "comment_nofollow" => "1", "language" => "en",
  "custom_form_types" => %([js]\nmediatype="application/javascript"\ntitle="JavaScript")
}
prefs.each { |k, v| Pref.set(k, v) }

User.create!(user_id: 1, name: "admin", RealName: "Site Administrator", email: "admin@example.com", privs: 1, password: "admin123")
User.create!(user_id: 2, name: "maria", RealName: "Maria Silva", email: "maria@example.com", privs: 2, password: "admin123")

Skin.create!(name: "cmp", title: "Compare", version: "1.0", description: "", author: "", author_uri: "") unless ENV["THEME"].present?
dir = ENV["THEME"].present? ? "/nonexistent" : File.join(__dir__, "theme")
Dir[File.join(dir, "pages", "*.txp")].each { |f| Page.create!(name: File.basename(f, ".txp"), skin: "cmp", user_html: File.read(f)) }
Dir[File.join(dir, "forms", "*", "*.txp")].each { |f| Form.create!(name: File.basename(f, ".txp"), type: File.basename(File.dirname(f)), skin: "cmp", Form: File.read(f)) }
Style.create!(name: "default", skin: "cmp", css: "body { color: #333; }") unless ENV["THEME"].present?

# THEME=path/to/textpattern/theme uses that theme (e.g. Textpattern's own
# four-point-nine) for every section instead of script/oracle/theme.
if (theme_dir = ENV["THEME"].presence)
  Txp::ThemeIO.import(theme_dir, name: "cmp", overwrite: true)
  Skin.where(name: "cmp").update_all(title: "Compare")
end

[ [ "default", "", "default", 0, 1, 1 ], [ "articles", "Articles", "archive", 1, 1, 1 ], [ "about", "About us", "archive", 0, 0, 1 ],
 [ "news", "News & views", "archive", 1, 1, 0 ], [ "cov", "Coverage", "coverage", 0, 0, 0 ], [ "gone", "Gone", "gone", 0, 0, 0 ],
 [ "private", "Private", "private", 0, 0, 0 ], [ "probe", "Probe", "probe", 0, 0, 0 ] ].each do |name, title, page, front, rss, search|
  Section.create!(name: name, title: title, skin: "cmp", page: page, css: "default", on_frontpage: front, in_rss: rss, searchable: search)
end

%w[article image file link].each { |t| Category.create!(type: t, name: "root", title: "root", parent: "") }
[ [ "article", "tech", "Technology", "root" ], [ "article", "ruby", "Ruby", "tech" ], [ "article", "rails", "Rails", "ruby" ],
 [ "article", "php", "PHP", "tech" ], [ "article", "life", "Life & stuff", "root" ], [ "link", "friends", "Friends", "root" ],
 [ "image", "photos", "Photos", "root" ], [ "file", "docs", "Documents", "root" ] ].each do |type, name, title, parent|
  Category.create!(type: type, name: name, title: title, parent: parent, description: "#{title} description")
end
%w[article image file link].each { |t| Category.rebuild_tree(t) }

base = Time.utc(2025, 6, 1, 10, 30, 0)
articles = [
  [ "hello-world", "Hello world", "articles", "tech", "", "admin", 0, "Hello *world*, this is the first article about Ruby.", "", "red", "S", "alpha,beta" ],
  [ "ruby-tips", "Ruby tips & tricks", "articles", "ruby", "life", "maria", 1, "Some _Ruby_ tips.\n\nSecond paragraph with a \"link\":https://example.com.", "Ruby tips excerpt", "blue", "M", "beta" ],
  [ "rails-guide", "A Rails guide", "articles", "rails", "", "admin", 2, "bq. A quote\n\n* one\n* two", "", "red", "L", "gamma" ],
  [ "php-notes", "PHP <notes>", "news", "php", "tech", "maria", 3, "h3. Heading\n\nText with <txp:site_name /> inside.", "PHP excerpt", "", "", "" ],
  [ "about-page", "About this site", "about", "", "", "admin", 4, "About us text.", "", "", "", "" ],
  [ "life-story", "Life story", "articles", "life", "", "maria", 5, "Life happens.", "", "green", "S", "alpha" ],
  [ "old-news", "Old news", "news", "", "", "admin", 40, "Old.", "", "", "", "" ],
  [ "sticky-post", "Sticky post", "articles", "tech", "", "admin", 6, "I stick.", "", "", "", "" ],
  [ "draft-post", "Draft post", "articles", "tech", "", "admin", 7, "Draft.", "", "", "", "" ]
]
articles.each_with_index do |(url, title, sec, c1, c2, author, days, body, excerpt, color, size, kw), i|
  status = url == "sticky-post" ? 5 : (url == "draft-post" ? 1 : 4)
  Article.create!(ID: i + 1, Title: title, url_title: url, Section: sec, Category1: c1, Category2: c2, AuthorID: author,
    Posted: base - days.days, LastMod: base - days.days + 3600, Body: body, Excerpt: excerpt, custom_1: color, custom_2: size,
    Keywords: kw, Status: status, Annotate: 1, AnnotateInvite: "Comment", textile_body: "1", textile_excerpt: "1",
    uid: Digest::MD5.hexdigest(url), feed_time: (base - days.days).to_date, description: "#{title} description")
end
Article.where(ID: 1..9).each { |a| a.update_columns(LastMod: a.Posted + 3600) }
Article.where(ID: 2).update_all(Expires: Time.utc(2030, 1, 1, 12, 0, 0))
Article.where(ID: 3).update_all(Annotate: 0)

Link.create!(id: 1, linkname: "Textpattern", url: "https://textpattern.com/", category: "friends", description: "The CMS", linksort: "Textpattern", date: base, author: "admin")
Link.create!(id: 2, linkname: "Ruby & Rails", url: "https://rubyonrails.org/", category: "", description: "", linksort: "Rails", date: base - 1.day, author: "maria")

Comment.create!(discussid: 1, parentid: 1, name: "Ann", email: "ann@example.com", web: "ann.example.com", posted: base + 1.hour, message: "<p>First!</p>", visible: 1)
Comment.create!(discussid: 2, parentid: 1, name: "Bob", email: "bob@example.com", web: "", posted: base + 2.hours, message: "<p>Second <strong>comment</strong></p>", visible: 1)
Comment.create!(discussid: 3, parentid: 1, name: "Spammer", email: "s@example.com", web: "", posted: base + 3.hours, message: "<p>spam</p>", visible: -1)
Article.update_comments_count(1)

Image.create!(id: 1, name: "photo.jpg", category: "photos", ext: ".jpg", w: 640, h: 480, alt: "A photo", caption: "Nice photo", date: base, author: "admin", thumbnail: 1, thumb_w: 100, thumb_h: 75)
Image.create!(id: 2, name: "logo.png", category: "", ext: ".png", w: 200, h: 200, alt: "", caption: "", date: base - 1.day, author: "maria", thumbnail: 0)
Article.where(ID: 1).update_all(Image: "1")
Article.where(ID: 2).update_all(Image: "1,2")
TxpFile.create!(id: 1, filename: "manual.pdf", title: "The manual", category: "docs", permissions: "0", description: "PDF manual", downloads: 7, status: 4, modified: base, created: base, size: 123456, author: "admin")

# The file itself, in Textpattern's files/ directory and in a directory of its
# own for the Rails side (set as file_base_path only there).
root = File.expand_path("../..", __dir__)
pdf = "%PDF-1.4\n% oracle test file\n%%EOF\n"
FileUtils.mkdir_p(File.join(root, "tmp/oracle/web/files"))
File.write(File.join(root, "tmp/oracle/web/files/manual.pdf"), pdf)
rails_files = File.join(root, "tmp/oracle/rails-files")
FileUtils.mkdir_p(rails_files)
File.write(File.join(rails_files, "manual.pdf"), pdf)
Pref.set("file_base_path", rails_files)

# ---- MySQL export ----
def q(v)
  case v
  when nil then "NULL"
  when Integer, Float then v.to_s
  when Time, DateTime, ActiveSupport::TimeWithZone then "'#{v.utc.strftime('%Y-%m-%d %H:%M:%S')}'"
  when Date then "'#{v.strftime('%Y-%m-%d')}'"
  else "'#{v.to_s.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'").gsub("\n", '\\n').gsub("\r", '\\r')}'"
  end
end

sql = +"SET NAMES utf8mb4;\nSET time_zone = '+00:00';\n"
TABLES.each do |t|
  sql << "DELETE FROM #{t};\n"
  rows = conn.select_all("SELECT * FROM #{t}")
  rows.each do |r|
    cols = r.keys.map { |c| "`#{c}`" }.join(", ")
    vals = r.values.map { |v| q(v) }.join(", ")
    sql << "INSERT INTO #{t} (#{cols}) VALUES (#{vals});\n"
  end
  # Restart ids after the loaded rows, as the fresh SQLite database does.
  sql << "ALTER TABLE #{t} AUTO_INCREMENT = 1;\n"
end
# Values Textpattern's setup leaves at their defaults, or generates randomly.
stamps = { "lastmod" => "2005-07-23 16:24:10", "blog_time_uid" => "2005", "blog_uid" => "0123456789abcdef0123456789abcdef",
           "blog_mail_uid" => "blog@example.com" }
stamps.each { |k, v| Pref.set(k, v) }
prefs.merge(stamps).each { |k, v| sql << "UPDATE txp_prefs SET val = #{q(v)} WHERE name = #{q(k)} AND user_name = '';\n" }
# now() caches the next scheduled change in sql_now_* prefs; content loaded
# behind Textpattern's back must invalidate them (as saving an article does).
sql << "UPDATE txp_prefs SET val = '0' WHERE name LIKE 'sql_now_%';\n"
sql << "DELETE FROM txp_users WHERE name = 'maria';\n"
sql << "INSERT INTO txp_users (name, pass, RealName, email, privs, nonce) VALUES ('maria', '#{User.find_by(name: 'maria').pass.sub('$2a$', '$2y$')}', 'Maria Silva', 'maria@example.com', 2, 'n');\n"
sql << "UPDATE txp_users SET RealName = 'Site Administrator' WHERE name = 'admin';\n"
File.write(out_path, sql)
puts "wrote #{out_path} (#{sql.lines.size} lines)"
