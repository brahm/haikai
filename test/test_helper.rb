ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Tests build their site in a transaction (TxpTestSite.install!), so start
# from empty tables whatever was left there, e.g. by the seeds step of bin/ci.
ActiveRecord::Base.with_connection { |conn| conn.truncate_tables(*conn.tables) }

# Builds a small Textpattern site used by the tests.
module TxpTestSite
  module_function

  def install!
    Txp::DefaultPrefs.install!("language" => "en", "language_ui" => "en", "production_status" => "debug")
    Pref.set("production_status", "debug", event: "site")
    Pref.set("permlink_mode", "section_title", event: "site")
    Pref.set("dateformat", "%Y-%m-%d", event: "site")
    Pref.set("archive_dateformat", "%Y-%m-%d", event: "site")
    Pref.set("comments_moderate", "0", event: "comments")
    Pref.set("comments_disabled_after", "0", event: "comments")
    Skin.create!(name: "test", title: "Test")
    Page.create!(name: "default", skin: "test", user_html: "<txp:article />")
    Style.create!(name: "default", skin: "test", css: "body{color:red}")
    Form.create!(name: "default", skin: "test", type: "article", Form: "<h2><txp:title /></h2><txp:body />")
    Form.create!(name: "comments", skin: "test", type: "comment", Form: "<p><txp:comment_name link=\"0\" />: <txp:comment_message /></p>")
    Form.create!(name: "comment_form", skin: "test", type: "comment", Form: "<txp:comment_name_input /><txp:comment_email_input /><txp:comment_message_input /><txp:comment_preview /><txp:comment_submit />")
    Form.create!(name: "comments_display", skin: "test", type: "comment", Form: "<txp:comments /><txp:comments_form />")
    Form.create!(name: "files", skin: "test", type: "file", Form: "<txp:file_download_name />")
    Form.create!(name: "plainlinks", skin: "test", type: "link", Form: "<txp:linkdesctitle />")
    Form.create!(name: "search_results", skin: "test", type: "article", Form: "<li><txp:title /></li>")

    Section.create!(name: "default", title: "Home", skin: "test", page: "default", css: "default", on_frontpage: 0)
    Section.create!(name: "articles", title: "Articles", skin: "test", page: "default", css: "default")
    Section.create!(name: "about", title: "About us", skin: "test", page: "default", css: "default", on_frontpage: 0, in_rss: 0)

    %w[article image file link].each { |t| Category.create!(type: t, name: "root", title: "root") }
    Category.create!(type: "article", name: "news", title: "News", parent: "root")
    Category.create!(type: "article", name: "ruby", title: "Ruby", parent: "root")
    Category.create!(type: "article", name: "rails", title: "Rails", parent: "ruby")
    Category.create!(type: "link", name: "friends", title: "Friends", parent: "root")
    %w[article image file link].each { |t| Category.rebuild_tree(t) }

    User.create!(name: "alice", RealName: "Alice Author", email: "alice@example.com", privs: 1, password: "secret123")
    User.create!(name: "bob", RealName: "Bob Writer", email: "bob@example.com", privs: 4, password: "secret123")

    base = Time.utc(2026, 3, 10, 12, 0, 0)
    @articles = {}
    [
      [ "first", "First post", "articles", "news", "", "alice", 5, { "Keywords" => "alpha,beta", "custom_1" => "red" } ],
      [ "second", "Second post", "articles", "ruby", "news", "bob", 4, { "Keywords" => "beta", "custom_1" => "blue", "Excerpt" => "Short *excerpt*" } ],
      [ "third", "Third post", "articles", "rails", "", "alice", 3, { "custom_1" => "red" } ],
      [ "about-us", "About us page", "about", "", "", "alice", 2, {} ],
      [ "draft-one", "Draft article", "articles", "news", "", "bob", 1, { "Status" => Txp::STATUS_DRAFT } ],
      [ "sticky-one", "Sticky article", "articles", "news", "", "alice", 6, { "Status" => Txp::STATUS_STICKY } ],
      [ "future-one", "Future article", "articles", "news", "", "alice", :future, {} ]
    ].each do |url_title, title, section, c1, c2, author, days_ago, extra|
      @articles[url_title] = Article.create!({
        "Title" => title, "url_title" => url_title, "Section" => section, "Category1" => c1, "Category2" => c2,
        "AuthorID" => author, "Status" => Txp::STATUS_LIVE, "Posted" => days_ago == :future ? Time.now.utc + 30.days : base - days_ago.days, "Annotate" => 1,
        "Body" => "Body of #{title}.", "textile_body" => Txp::USE_TEXTILE, "textile_excerpt" => Txp::USE_TEXTILE
      }.merge(extra))
    end
    Link.create!(linkname: "Example", url: "https://example.com/", category: "friends", description: "An example", linksort: "a")
    Link.create!(linkname: "Rails", url: "https://rubyonrails.org/", category: "", description: "", linksort: "b")
    @articles
  end

  def articles
    @articles
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    # Renders markup with a fresh renderer (optionally routed to a path).
    def render_txp(markup, path: "/", params: {}, prefs: {}, user: nil)
      renderer = build_renderer(path: path, params: params, prefs: prefs, user: user)
      renderer.render_string(markup)
    end

    def build_renderer(path: "/", params: {}, prefs: {}, user: nil)
      query = params.empty? ? "" : "?#{params.to_query}"
      env = Rack::MockRequest.env_for("http://example.com#{path}#{query}")
      request = ActionDispatch::Request.new(env)
      renderer = Txp::Renderer.new(request: request, prefs: Pref.site_prefs.merge(prefs.transform_keys(&:to_s)), user: user)
      renderer.pretext!
      @last_renderer = renderer
      renderer
    end

    def last_errors
      @last_renderer&.errors&.join
    end

    def squish(html)
      html.to_s.gsub(/\s+/, " ").strip
    end
  end
end

# Helpers for public-site responses.
module TxpResponseHelpers
  # The page without the trace summary/log Textpattern appends outside live mode.
  def page_body
    response.body.sub(/\n<!-- Trace summary:.*\z/m, "").strip
  end
end
ActionDispatch::IntegrationTest.include(TxpResponseHelpers)
