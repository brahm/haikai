require "test_helper"

class PublicSiteTest < ActionDispatch::IntegrationTest
  setup do
    @a = TxpTestSite.install!
    Page.find_by(name: "default", skin: "test").update!(user_html: <<~HTML)
      <title><txp:page_title /></title>
      <txp:if_individual_article>[single:<txp:article><txp:title /></txp:article>]<txp:output_form form="comments_display" /><txp:else />[list:<txp:section />:<txp:category />:<txp:if_author><txp:author /></txp:if_author>]<txp:article break="|"><txp:title /></txp:article></txp:if_individual_article>
    HTML
  end

  def with_mode(mode)
    Pref.set("permlink_mode", mode, event: "site")
  end

  test "home page lists front page articles" do
    get "/"
    assert_response :success
    assert_includes response.body, "[list:"
    assert_includes response.body, "First post"
    refute_includes response.body, "About us page" # about is not on the front page
    refute_includes response.body, "Draft article"
  end

  test "section_title URLs" do
    get "/articles/second"
    assert_response :success
    assert_includes response.body, "[single:Second post]"
    assert_includes response.body, "<title>Second post | My site</title>"
    get "/articles/"
    assert_includes response.body, "[list:articles:"
    get "/articles/draft-one"
    assert_response :not_found
  end

  test "all permanent link modes resolve" do
    id = @a["second"].ID
    {
      "section_id_title" => "/articles/#{id}/second",
      "year_month_day_title" => "/2026/03/06/second",
      "title_only" => "/second",
      "id_title" => "/#{id}/second",
      "section_category_title" => "/articles/ruby/news/second",
      "breadcrumb_title" => "/articles/ruby/news/second",
      "messy" => "/index.php?id=#{id}"
    }.each do |mode, path|
      with_mode(mode)
      get path
      assert_response :success, "#{mode} #{path}"
      assert_includes response.body, "[single:Second post]", mode
    end
  end

  test "messy query parameters" do
    get "/", params: { s: "about" }
    assert_includes response.body, "[list:about"
    get "/", params: { c: "news" }
    assert_includes response.body, "[list:default:news:]"
  end

  test "category and author lists" do
    get "/category/ruby/"
    assert_response :success
    assert_includes response.body, "[list:default:ruby:]"
    assert_includes response.body, "Second post"
    refute_includes response.body, "First post"
    get "/author/Bob+Writer/"
    assert_response :success
    assert_includes response.body, "Second post"
    refute_includes response.body, "Third post"
  end

  test "unknown pages and categories are 404" do
    get "/nope/nothing-here"
    assert_response :not_found
    get "/category/unknown/"
    assert_response :not_found
  end

  test "expired articles are 410 gone" do
    @a["third"].update!(Expires: 1.day.ago.utc)
    get "/articles/third"
    assert_response :gone
  end

  test "error pages use error_default" do
    Page.create!(name: "error_default", skin: "test", user_html: "ERR <txp:error_status />: <txp:error_message />")
    get "/nope/x"
    assert_response :not_found
    assert_equal "ERR 404 Not Found: The requested resource was not found.", page_body
  end

  test "search" do
    get "/", params: { q: "Third" }
    assert_includes response.body, "<li>Third post</li>"
  end

  test "rss and atom feeds" do
    get "/rss/"
    assert_response :success
    assert_equal "application/rss+xml", response.media_type
    doc = Nokogiri::XML(response.body)
    assert_equal "My site", doc.at_xpath("//channel/title").text
    assert_includes doc.xpath("//item/title").map(&:text), "First post"
    refute_includes doc.xpath("//item/title").map(&:text), "About us page"

    get "/atom/"
    assert_equal "application/atom+xml", response.media_type
    doc = Nokogiri::XML(response.body)
    doc.remove_namespaces!
    assert_includes doc.xpath("//entry/title").map(&:text), "Second post"

    get "/", params: { rss: 1, category: "ruby" }
    doc = Nokogiri::XML(response.body)
    assert_equal [ "Second post" ], doc.xpath("//item/title").map(&:text)
  end

  test "css.php" do
    get "/css.php", params: { n: "default", t: "test" }
    assert_response :success
    assert_equal "text/css", response.media_type
    assert_equal "body{color:red}", response.body
  end

  test "file downloads count downloads" do
    path = TxpFile.base_path.join("hello.txt")
    File.write(path, "hello")
    file = TxpFile.create!(filename: "hello.txt", status: 4, size: 5, description: "")
    get "/file_download/#{file.id}/hello.txt"
    assert_response :success
    assert_equal "hello", response.body
    assert_equal 1, file.reload.downloads
  ensure
    FileUtils.rm_f(path) if path
  end

  test "comment preview and submit" do
    article = @a["first"]
    get "/articles/first"
    assert_includes response.body, "txpCommentInputForm"

    post "/articles/first", params: { name: "Ann", email: "ann@example.com", message: "Nice *post*", parentid: article.ID, backpage: "/articles/first", preview: "Preview" }
    assert_response :success
    html = Nokogiri::HTML(response.body)
    textarea = html.at_css("textarea.txpCommentInputMessage")
    msg_field = textarea["name"]
    assert_match(/\A\h{32}\z/, msg_field)
    nonce_input = html.css("input[type=hidden]").find { |i| i["name"].match?(/\A\h+\z/) && "#{i['name']}#{i['value']}".length == 32 }
    assert nonce_input

    post "/articles/first", params: {
      name: "Ann", email: "ann@example.com", msg_field => "Nice *post*", nonce_input["name"] => nonce_input["value"],
      parentid: article.ID, backpage: "/articles/first", submit: "Submit"
    }
    assert_response :redirect
    assert_match %r{/articles/first\?commented=1#c\d+}, response.location
    comment = Comment.last
    assert_equal "Ann", comment.name
    assert_equal "<p>Nice <strong>post</strong></p>", comment.message
    assert_equal 1, article.reload.comments_count

    get "/articles/first"
    assert_includes response.body, "Ann"
  end

  test "comment without nonce is not saved" do
    post "/articles/first", params: { name: "Spam", email: "s@example.com", message: "spam", parentid: @a["first"].ID, submit: "Submit" }
    assert_equal 0, Comment.count
  end
end
