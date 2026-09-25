# Installs a fresh Textpattern-on-Rails site (like Textpattern's setup):
# preferences, the default theme, sections, categories, an admin user and a
# welcome article. Safe to run more than once. Alternatively, open
# /textpattern/ on an empty database to use the web installer.
#
#   ADMIN_USER=admin ADMIN_PASS=secret ADMIN_EMAIL=me@example.com bin/rails db:seed
#   SITE_LANG=pt-br SITE_NAME="Meu site" bin/rails db:seed

admin_name = ENV.fetch("ADMIN_USER", "admin")
user = User.find_by(name: admin_name)
password = nil

unless user
  password = ENV.fetch("ADMIN_PASS") { SecureRandom.alphanumeric(12) }
  user = User.new(name: admin_name, RealName: "Site Administrator", email: ENV.fetch("ADMIN_EMAIL", "admin@example.com"), privs: 1, password: password)
end

Txp::Installer.install!(sitename: ENV.fetch("SITE_NAME", "My site"), lang: ENV.fetch("SITE_LANG", "en"), user: user)

puts "Admin user created: #{admin_name} / #{password}" if password
puts "Site installed. Admin panel: /textpattern/"
