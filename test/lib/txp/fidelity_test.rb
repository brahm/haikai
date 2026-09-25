require "test_helper"

# Behaviours of the real Textpattern 4.9 found with the differential oracle
# (script/oracle), including its quirks, pinned down here so they do not
# regress when the oracle is not running.
class Txp::FidelityTest < ActiveSupport::TestCase
  setup { TxpTestSite.install! }

  test "localisation strings come from Textpattern's own language files" do
    assert_equal "Comment", render_txp('<txp:text item="comment" />')
    assert_equal "Yes", Txp::Textpack.txt("en", "yes") # stored as txp_yes
    assert_equal "Sim", Txp::Textpack.txt("pt-br", "yes")
    assert_includes Txp::Textpack.available, "de"
  end

  test "public side only sees public and common strings" do
    # "edit_comment" is an admin-side string.
    assert_equal "edit_comment", render_txp('<txp:text item="edit_comment" />')
    assert_equal "Edit comment", Txp::Textpack.txt("en", "edit_comment")
  end

  test "comments_help and popup_comments are unknown tags, as in Textpattern 4.9" do
    assert_equal "[]", render_txp("[<txp:comments_help />]", prefs: { production_status: "testing" })
    assert_includes last_errors, "comments_help tag does not exist"
    render_txp("<txp:popup_comments />", prefs: { production_status: "testing" })
    assert_includes last_errors, "popup_comments tag does not exist"
  end

  test "if_request type=request only works once a tag class was autoloaded" do
    markup = '[<txp:if_request name="q">Q<txp:else />none</txp:if_request>]'
    assert_equal "[none]", render_txp(markup, params: { q: "x" })
    assert_match(/\[Q\]\z/, render_txp("<txp:linklist />#{markup}", params: { q: "x" }))
    assert_equal "[Q]", render_txp(markup.sub('name="q"', 'name="q" type="get"'), params: { q: "x" })
  end

  test "live sites carry on with an empty context instead of aborting the tag" do
    live = { production_status: "live" }
    assert_equal '<a id="c"></a>', render_txp("<txp:comment_anchor />", prefs: live)
    assert_equal "&#8230;<strong></strong> &#8230;", render_txp("<txp:search_result_excerpt />", prefs: live)
    assert_equal "[no]", render_txp("[<txp:if_comments_allowed>yes<txp:else />no</txp:if_comments_allowed>]", prefs: live)
    assert_equal "", render_txp("<txp:title />", prefs: live)
  end

  test "context errors are reported outside live mode" do
    render_txp("<txp:title />", prefs: { production_status: "debug" })
    assert_includes last_errors, "Article tags cannot be used outside an article context."
    assert_includes last_errors, "</b> -> <b> Textpattern Notice:"
  end

  test "comment inputs outside comments_form warn like PHP" do
    render_txp("<txp:comment_message_input />", prefs: { production_status: "testing" })
    assert_equal 3, last_errors.scan("Warning: Trying to access array offset on null").size
  end

  test "php code is never run and its error stays inline" do
    out = render_txp("[<txp:php>echo 1;</txp:php>]", prefs: { production_status: "debug" })
    assert_match %r{\A\[<pre dir="auto">Tag error: .*PHP code is disabled for pages\..*</pre>\]\z}m, out
    assert_empty last_errors.to_s
  end

  test "json escaping matches json_encode" do
    markup = %q(<txp:variable name="u" value='http://example.com/a "b"' /><txp:variable name="u" escape="json" />)
    assert_equal 'http:\/\/example.com\/a \"b\"', render_txp(markup)
  end
end

class Txp::FidelityPublicTest < ActionDispatch::IntegrationTest
  setup { TxpTestSite.install! }

  test "testing mode appends Textpattern's trace summary" do
    Pref.set("production_status", "testing")
    get "/"
    assert_match(/\n<!-- Trace summary:\nRuntime   : [\d.]+ ms\nQuery time: [\d.]+ ms\nQueries   : \d+\nMemory \(\*\): \d+ kB\nPages     : default\n/, response.body)
    assert_equal "no-cache, no-store, max-age=0", response.headers["Cache-Control"]
  end

  test "live mode sends Last-Modified and ETag and answers 304" do
    Pref.set("production_status", "live")
    get "/"
    assert_response :success
    etag = response.headers["ETag"]
    assert_match(/\A"[0-9a-v]+"\z/, etag)
    assert_nil response.headers["Cache-Control"]
    get "/", headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "atom link feeds follow atom.php" do
    Link.create!(linkname: "Rails & co", url: "/local?a=1&b=2", category: "friends", description: "", date: Time.utc(2025, 1, 2), author: "alice")
    get "/?atom=1&area=link"
    assert_response :success
    assert_includes response.body, '<content type="html"><![CDATA[]]></content>'
    assert_includes response.body, 'href="https?://www.example.com/local?a=1&amp;b=2"'
    assert_match(%r{<id>tag:www\.example\.com,2025-01-02:[0-9a-f]+/\d+</id>}, response.body)
  end
end
