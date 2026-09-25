require "test_helper"

# Links sent by email use the site URL preference, never the Host header of
# the request, which anyone can forge (password reset poisoning).
class EmailLinksTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    TxpTestSite.install!
    ActionMailer::Base.deliveries.clear
  end

  def request_reset
    perform_enqueued_jobs do
      post "/textpattern/index.php", params: { p_reset: "1", p_userid: "alice" }
    end
    assert_response :success
    assert_includes response.body, "messageflash success"
  end

  test "reset links point at the site URL, whatever the Host header says" do
    Pref.set("siteurl", "www.example.com", event: "site")
    host! "evil.example"
    request_reset
    body = ActionMailer::Base.deliveries.sole.body.to_s
    assert_match %r{http://www\.example\.com/textpattern/index\.php\?confirm=\h{52}&lang=en}, body
    assert_not_includes body, "evil.example"
  end

  test "no reset link goes out before the site URL is known" do
    request_reset
    assert_empty ActionMailer::Base.deliveries
    assert_not Token.exists?(type: "password_reset")
  end

  test "the first login records the site URL" do
    host! "cms.example.org"
    post "/textpattern/index.php", params: { p_userid: "alice", p_password: "secret123" }
    assert_equal "cms.example.org", Pref.get("siteurl")

    host! "other.example"
    post "/textpattern/index.php", params: { p_userid: "alice", p_password: "secret123" }
    assert_equal "cms.example.org", Pref.get("siteurl")
  end

  test "activation links of new users follow the admin's own host until the site URL is set" do
    post "/textpattern/index.php", params: { p_userid: "alice", p_password: "secret123" }
    Pref.set("siteurl", "", event: "site")
    perform_enqueued_jobs do
      post "/textpattern/index.php", params: { event: "admin", step: "author_save", name: "carol", RealName: "Carol", email: "carol@example.com", privs: 3 }
    end
    assert_match %r{http://www\.example\.com/textpattern/index\.php\?activate=\h{52}&lang=en}, ActionMailer::Base.deliveries.sole.body.to_s
  end
end

class WebInstallerTest < ActionDispatch::IntegrationTest
  test "the web installer records the site URL" do
    host! "new.example.net"
    post "/textpattern/index.php", params: { name: "owner", RealName: "Owner", email: "owner@example.com", password: "secret123", sitename: "New", lang: "en" }
    assert_response :redirect
    assert_equal "new.example.net", Pref.get("siteurl")
  end
end

class SeedsSiteUrlTest < ActiveSupport::TestCase
  test "SITE_URL gives a command-line install its site URL" do
    ENV["SITE_URL"] = "https://www.example.org/"
    capture_io { load Rails.root.join("db", "seeds.rb").to_s }
    assert_equal "www.example.org", Pref.get("siteurl")
  ensure
    ENV.delete("SITE_URL")
  end
end
