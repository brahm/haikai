require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup { @a = TxpTestSite.install! }

  def login(name = "alice", pass = "secret123")
    post "/textpattern/index.php", params: { p_userid: name, p_password: pass }
    assert_response :redirect
  end

  test "login required" do
    get "/textpattern/index.php", params: { event: "list" }
    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "txp-login"
  end

  test "/admin leads to the admin side unless a section is called admin" do
    get "/admin"
    assert_redirected_to "/textpattern/"
    get "/admin/"
    assert_redirected_to "/textpattern/"

    Section.create!(name: "admin", title: "Admin", skin: "test", page: "default", css: "default")
    get "/admin/"
    assert_response :success
    assert_not_includes response.body, "txp-login"
  end

  test "list panels sort by each column, both ways" do
    login
    { "list" => Admin::ListController, "image" => Admin::ImagesController, "file" => Admin::FilesController,
      "link" => Admin::LinksController, "discuss" => Admin::CommentsController, "log" => Admin::LogsController,
      "section" => Admin::SectionsController, "admin" => Admin::UsersController }.each do |event, controller|
      controller::SORTS.each_key do |sort|
        %w[asc desc].each do |dir|
          get "/textpattern/index.php", params: { event: event, sort: sort, dir: dir }
          assert_response :success, "#{event} by #{sort} #{dir}"
        end
      end
    end

    titles = -> { Nokogiri::HTML(response.body).css("td.txp-list-col-title a").map(&:text) }
    get "/textpattern/index.php", params: { event: "list", sort: "title", dir: "asc" }
    ascending = titles.call
    assert_operator ascending.size, :>, 1
    assert_equal ascending.sort, ascending
    get "/textpattern/index.php", params: { event: "list", sort: "title", dir: "desc" }
    assert_equal ascending.reverse, titles.call
  end

  test "sort parameters outside the lists fall back to the defaults" do
    login
    get "/textpattern/index.php", params: { event: "list", sort: "title", dir: "desc, (SELECT 1)" }
    assert_response :success
    get "/textpattern/index.php", params: { event: "list", sort: "Title; DROP TABLE textpattern", dir: "asc" }
    assert_response :success
    assert Article.exists?
  end

  test "diagnostics have a low and a high detail level and can hide private information" do
    login
    report = -> { css_select("#diagnostic-info").text }
    get "/textpattern/index.php", params: { event: "diag" }
    assert_response :success
    assert_select "select#diag_detail_level option[selected][value=low]"
    assert_includes report.call, "Site URL (request): http://www.example.com/"
    assert_not_includes report.call, "Database check"

    get "/textpattern/index.php", params: { event: "diag", step: "high" }
    assert_select "select#diag_detail_level option[selected][value=high]"
    assert_includes report.call, "Database check: ok"
    assert_match(/^Database tables \(\d+\): .*\btextpattern \(7\)/, report.call)
    assert_match(/^Gems: .*\brails-8\./, report.call)

    get "/textpattern/index.php", params: { event: "diag", step: "high", clear_private: "1" }
    assert_includes report.call, "Database check: ok"
    [ "Site URL", "Admin URL", "Document root", "directory:" ].each { |text| assert_not_includes report.call, text }
  end

  test "bad password" do
    post "/textpattern/index.php", params: { p_userid: "alice", p_password: "wrong" }
    assert_response :unauthorized
  end

  test "inline help comes from Textpattern's pophelp files" do
    login
    get "/textpattern/index.php", params: { event: "prefs" }
    assert_includes response.body, 'href="/textpattern/index.php?event=help&amp;item=sitename&amp;step=pophelp"'
    get "/textpattern/index.php", params: { event: "help", step: "pophelp", item: "sitename" }, xhr: true
    assert_response :success
    assert_match %r{\A<div id="pophelp-event" dir="auto"><h2>Site name</h2>}, response.body
    get "/textpattern/index.php", params: { event: "help", step: "pophelp", item: "../etc" }, xhr: true
    assert_response :bad_request
    Pref.set("module_pophelp", "0", event: "admin")
    get "/textpattern/index.php", params: { event: "prefs" }
    assert_not_includes response.body, "step=pophelp"
  end

  test "all panels render for a publisher" do
    login
    %w[article list image file link discuss category skin section page form css diag prefs admin lang plugin tag].each do |ev|
      get "/textpattern/index.php", params: { event: ev }
      assert_response :success, ev
      assert_includes response.body, 'class="txp-header"', ev
    end
  end

  test "restricted panels for a staff writer" do
    login("bob")
    get "/textpattern/index.php", params: { event: "page" }
    assert_response :forbidden
    get "/textpattern/index.php", params: { event: "article" }
    assert_response :success
  end

  test "write, publish and edit an article" do
    login
    post "/textpattern/index.php", params: { event: "article", step: "publish", Title: "Hello Rails", Body: "Some *text*", Section: "articles", Status: 4, textile_body: "1" }
    assert_response :redirect
    art = Article.find_by(Title: "Hello Rails")
    assert_equal "hello-rails", art.url_title
    assert_equal "<p>Some <strong>text</strong></p>", art.Body_html
    assert_equal "alice", art.AuthorID

    post "/textpattern/index.php", params: { event: "article", step: "save", ID: art.ID, Title: "Hello again", Body: "x", Section: "about", Status: 1, url_title: "hello-rails" }
    art.reload
    assert_equal [ "Hello again", "about", 1 ], [ art.Title, art.Section, art.Status ]

    get "/about/hello-rails"
    assert_response :not_found
  end

  test "freelancers cannot publish" do
    User.create!(name: "fred", RealName: "Fred", email: "fred@example.com", privs: 5, password: "secret123")
    login("fred")
    post "/textpattern/index.php", params: { event: "article", step: "publish", Title: "Fred post", Body: "x", Section: "articles", Status: 4 }
    assert_equal Txp::STATUS_PENDING, Article.find_by(Title: "Fred post").Status
  end

  test "article list multi edit" do
    login
    ids = [ @a["first"].ID, @a["second"].ID ]
    post "/textpattern/index.php", params: { event: "list", step: "list_multi_edit", edit_method: "changestatus", Status: 2, selected: ids }
    assert_equal [ 2, 2 ], Article.where(ID: ids).pluck(:Status)
    post "/textpattern/index.php", params: { event: "list", step: "list_multi_edit", edit_method: "delete", selected: [ ids.first ] }
    refute Article.exists?(ID: ids.first)
  end

  test "edit page templates and sections" do
    login
    post "/textpattern/index.php", params: { event: "page", step: "page_save", skin: "test", name: "default", newname: "default", code: "NEW <txp:site_name />" }
    assert_response :redirect
    get "/"
    assert_equal "NEW My site", page_body

    post "/textpattern/index.php", params: { event: "form", step: "form_save", skin: "test", newname: "extra", type: "misc", code: "extra form" }
    assert Form.exists?(name: "extra", skin: "test", type: "misc")

    post "/textpattern/index.php", params: { event: "section", step: "section_save", title: "Blog", name: "blog", skin: "test", page: "default", css: "default", on_frontpage: 1, in_rss: 1, searchable: 1 }
    assert Section.exists?(name: "blog")
  end

  test "categories" do
    login
    post "/textpattern/index.php", params: { event: "category", step: "cat_create", type: "article", title: "Sub Rails", parent: "rails" }
    cat = Category.find_by(type: "article", name: "sub-rails")
    assert_equal "rails", cat.parent
    ruby = Category.find_by(type: "article", name: "ruby")
    assert cat.lft > ruby.lft && cat.rgt < ruby.rgt
  end

  test "preferences" do
    login
    post "/textpattern/index.php", params: { event: "prefs", step: "prefs_save", group: "site", prefs: { sitename: "Renamed", permlink_mode: "id_title" } }
    assert_equal "Renamed", Pref.get("sitename")
    assert_equal "id_title", Pref.get("permlink_mode")
  end

  test "no preferences for features left out" do
    login
    get "/textpattern/index.php", params: { event: "prefs", group: "admin" }
    assert_response :success
    assert_select "[name='prefs[img_dir]']"
    assert_select "[name='prefs[enable_xmlrpc_server]'], [name='prefs[plugin_cache_dir]']", count: 0
  end

  test "users" do
    login
    post "/textpattern/index.php", params: { event: "admin", step: "author_save", name: "carol", RealName: "Carol", email: "carol@example.com", privs: 3, password: "secret123" }
    assert User.find_by(name: "carol").authenticate("secret123")
  end

  test "plugins add tags" do
    login
    code = "# name: abc_hi\n# version: 1.0\ntag :abc_hi do |txp, atts, thing|\n  \"hi \#{atts['to']}\"\nend\n"
    post "/textpattern/index.php", params: { event: "plugin", step: "plugin_install", plugin: code }
    Plugin.find("abc_hi").update!(status: 1)
    Txp::Plugins.reset!
    Page.find_by(name: "default", skin: "test").update!(user_html: '<txp:abc_hi to="you" />')
    get "/"
    assert_equal "hi you", page_body
  ensure
    Txp::Registry.reset!
    Txp::Plugins.reset!
  end

  test "theme export and import round trip" do
    login
    dir = Rails.root.join("tmp", "test-theme-export")
    FileUtils.rm_rf(dir)
    Txp::ThemeIO.export("test", dir)
    assert File.exist?(dir.join("manifest.json"))
    assert File.exist?(dir.join("forms", "article", "default.txp"))
    Txp::ThemeIO.import(dir, name: "copy")
    assert_equal Form.where(skin: "test").count, Form.where(skin: "copy").count
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
