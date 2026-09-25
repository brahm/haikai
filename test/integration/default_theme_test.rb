require "test_helper"

# The site a fresh install starts with: Txp::Installer and db/themes/default.
class DefaultThemeTest < ActionDispatch::IntegrationTest
  setup do
    owner = User.new(name: "owner", RealName: "Owner", email: "owner@example.com", password: "secret123")
    Txp::Installer.install!(sitename: "Fresh site", user: owner)
    Pref.set("production_status", "testing")
    @article = Article.first
    Comment.create!(parentid: @article.ID, name: "Ann", email: "ann@example.com", message: "<p>Hello there</p>",
      visible: Txp::VISIBLE, posted: Time.now.utc)
  end

  # Follows the links (<a> and <link>) of the public pages from the front page.
  def crawl(*start, limit: 80)
    queue = start
    seen = {}
    while (path = queue.shift) && seen.size < limit
      next if seen.key?(path)

      get path
      seen[path] = response.status
      next unless response.media_type == "text/html"

      assert_not_includes response.body, "Tag error", path
      Nokogiri::HTML(response.body).css("a[href], link[href]").each do |node|
        uri = URI.join("http://www.example.com#{path}", node["href"]) rescue next
        queue << uri.request_uri if [ nil, "www.example.com" ].include?(uri.host) && !uri.path.start_with?("/textpattern")
      end
    end
    seen
  end

  test "a fresh site has no broken links or tag errors" do
    pages = crawl("/", "/?q=site")
    assert_operator pages.size, :>, 10
    assert_empty pages.reject { |_path, status| status == 200 }
    # About is left out of the feeds: its pages link to the site's feeds.
    assert pages.key?("/rss/")
    assert_not pages.keys.any? { |path| path.include?("section=about") }
  end

  test "the comments popup has a form in the theme" do
    # Opened by <txp:comments_invite /> when comments are a popup.
    Pref.set("comments_mode", "1")
    get "/", params: { parentid: @article.ID }
    assert_response :success
    assert_includes response.body, "Hello there"
    assert_select "body.popup-page form#txpCommentInputForm"
  end
end
