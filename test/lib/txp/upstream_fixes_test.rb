require "test_helper"

# Bugs of Textpattern 4.9 that this port fixes (it otherwise matches
# Textpattern's output byte for byte, see script/oracle). Each test notes what
# Textpattern itself does.
class Txp::UpstreamFixesTest < ActiveSupport::TestCase
  setup { TxpTestSite.install! }

  def first_article
    Article.find_by(url_title: "first")
  end

  test "comments_help renders the Textile help link" do
    # Textpattern: registered to a missing method, so "tag does not exist".
    assert_equal '<a id="txpCommentHelpLink" rel="external" target="_blank" href="https://textile-lang.com">Textile help</a>',
      render_txp("<txp:comments_help />", prefs: { production_status: "testing" })
    assert_empty last_errors
  end

  test "if_request with the default type sees GET and POST parameters" do
    # Textpattern: only once PHP happens to have created $_REQUEST.
    markup = '[<txp:if_request name="q">Q<txp:else />none</txp:if_request>]'
    assert_equal "[Q]", render_txp(markup, params: { q: "x" })
    assert_equal "[none]", render_txp(markup)
  end

  test "a self-closed form call has nothing to yield" do
    # Textpattern: <txp:yield /> prints "1" and <txp:if_yield> is true.
    Form.create!(name: "box", skin: "test", type: "misc", Form: '<txp:yield default="nothing" />')
    Form.create!(name: "iy", skin: "test", type: "misc", Form: "<txp:if_yield>yes<txp:else />no</txp:if_yield>")
    assert_equal "nothing|x", render_txp("<txp::box />|<txp::box>x</txp::box>")
    assert_equal "no|yes", render_txp("<txp::iy />|<txp::iy>x</txp::iy>")
  end

  test "a self-closed comment_permlink is the comment's URL" do
    # Textpattern: a link labelled "1".
    Comment.create!(parentid: first_article.ID, name: "Ann", email: "ann@example.com", message: "<p>Hi</p>", visible: 1, posted: Time.utc(2026, 3, 11))
    out = render_txp(%(<txp:article_custom id="#{first_article.ID}"><txp:comments><txp:comment_permlink /></txp:comments></txp:article_custom>))
    assert_match %r{<li>http://example.com/articles/first#c\d{6}\n</li>}, out
  end

  test "showalways without content prints nothing" do
    # Textpattern: "1".
    assert_equal "[]", render_txp(%(<txp:article_custom id="#{first_article.ID}">[<txp:link_to_prev showalways="1" />]</txp:article_custom>))
  end

  test "tags outside their context print nothing on live sites" do
    # Textpattern: they carry on with an empty context, e.g. <a id="c"></a>
    # or "Commenting is closed for this article.".
    live = { production_status: "live" }
    assert_equal "", render_txp("<txp:comment_anchor />", prefs: live)
    assert_equal "", render_txp("<txp:comments_form />", prefs: live)
    assert_equal "[]", render_txp("[<txp:if_comments_allowed>yes<txp:else />no</txp:if_comments_allowed>]", prefs: live)
    assert_empty last_errors
  end

  test "search_result_excerpt needs a search term" do
    # Textpattern: "&#8230;<strong></strong> &#8230;".
    assert_equal "[]", render_txp(%(<txp:article_custom id="#{first_article.ID}">[<txp:search_result_excerpt />]</txp:article_custom>))
  end

  test "comment inputs outside comments_form use its defaults" do
    # Textpattern: PHP "Trying to access array offset on null" warnings and
    # buttons without labels.
    testing = { production_status: "testing" }
    assert_includes render_txp("<txp:comment_preview />", prefs: testing), 'value="Preview"'
    assert_includes render_txp("<txp:comment_message_input />", prefs: testing), 'cols="25" rows="5"'
    assert_includes render_txp("<txp:comment_remember />", prefs: testing), ">Remember</label>"
    assert_empty last_errors
  end

  test "PHP notices do not leak into pages" do
    # Textpattern: strlen() deprecation for a self-closed if_different and a
    # mime_content_type() warning for files missing on disk.
    TxpFile.create!(filename: "missing.pdf", title: "Missing", status: Txp::STATUS_LIVE, created: Time.utc(2026, 1, 1), modified: Time.utc(2026, 1, 1))
    out = render_txp(%([<txp:if_different />][<txp:file_download id="#{TxpFile.last.id}"><txp:file_download_name /></txp:file_download>]),
      prefs: { production_status: "debug" })
    assert_equal "[1][missing.pdf]", out
    assert_empty last_errors
  end
end

class Txp::UpstreamFixesPublicTest < ActionDispatch::IntegrationTest
  setup { TxpTestSite.install! }

  test "popup comments work and are titled Comments on" do
    # Textpattern: popup_comments is never registered, and the title branch
    # reads a variable that is never set.
    Pref.set("comments_mode", "1", event: "comments")
    Form.create!(name: "popup_comments", skin: "test", type: "comment", Form: "<title><txp:page_title /></title><txp:popup_comments />")
    article = Article.find_by(url_title: "first")
    Comment.create!(parentid: article.ID, name: "Ann", email: "ann@example.com", message: "<p>Hi</p>", visible: 1, posted: Time.utc(2026, 3, 11))
    get "/", params: { parentid: article.ID }
    assert_response :success
    assert_includes response.body, "<title>Comments on First post | My site</title>"
    assert_includes response.body, "<p>Ann: <p>Hi</p></p>"
  end

  test "link feeds carry absolute, escaped URLs" do
    # Textpattern: Atom writes a literal "https?://" and a half-escaped URL.
    Link.create!(linkname: "Local", url: "/local?a=1&b=2", category: "friends", description: "", date: Time.utc(2025, 1, 2))
    get "/?atom=1&area=link&category=friends"
    assert_includes response.body, 'href="http://www.example.com/local?a=1&amp;b=2"'
    get "/?rss=1&area=link&category=friends"
    assert_includes response.body, "<link>http://www.example.com/local?a=1&amp;b=2</link>"
  end

  test "an empty link category has an empty feed titled with that category" do
    # Textpattern: 404, because the category is compared with "Array", and
    # feed titles use article categories.
    Category.create!(type: "link", name: "empty", title: "Empty links", parent: "root")
    get "/?atom=1&area=link&category=empty"
    assert_response :success
    assert_includes response.body, "<title type=\"text\">My site - Empty links</title>"
  end

  test "A-IM: feed returns only the entries newer than the client's copy" do
    # Textpattern: strpos() misses "feed" at the start of the header.
    Category.create!(type: "link", name: "news", title: "News links", parent: "root")
    Link.create!(linkname: "Old", url: "https://example.com/old", category: "news", date: Time.utc(2025, 1, 1))
    Link.create!(linkname: "New", url: "https://example.com/new", category: "news", date: Time.utc(2025, 6, 1))
    get "/?rss=1&area=link&category=news", headers: { "A-IM" => "feed", "If-Modified-Since" => "Sat, 01 Mar 2025 00:00:00 GMT" }
    assert_response 226
    assert_includes response.body, "<title>New</title>"
    assert_not_includes response.body, "<title>Old</title>"
  end
end
