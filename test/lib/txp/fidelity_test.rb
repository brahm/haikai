require "test_helper"

# Behaviours of the real Textpattern 4.9 found with the differential oracle
# (script/oracle), pinned down here so they do not regress when the oracle is
# not running. Textpattern bugs this port fixes are covered by
# upstream_fixes_test.rb instead.
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

  test "context errors are reported outside live mode" do
    render_txp("<txp:title />", prefs: { production_status: "debug" })
    assert_includes last_errors, "Article tags cannot be used outside an article context."
    assert_includes last_errors, "</b> -> <b> Textpattern Notice:"
  end

  test "php code is never run and its error stays inline" do
    out = render_txp("[<txp:php>echo 1;</txp:php>]", prefs: { production_status: "debug" })
    assert_match %r{\A\[<pre dir="auto">Tag error: .*PHP code is disabled for pages\..*</pre>\]\z}m, out
    assert_empty last_errors.to_s
  end

  test "file MIME types are sniffed from the file" do
    Dir.mktmpdir do |dir|
      Pref.set("file_base_path", dir)
      File.write(File.join(dir, "doc.bin"), "%PDF-1.4\n%%EOF\n")
      file = TxpFile.create!(filename: "doc.bin", title: "Doc", status: Txp::STATUS_LIVE, created: Time.utc(2026, 1, 1), modified: Time.utc(2026, 1, 1))
      out = render_txp(%(<txp:file_download id="#{file.id}"><txp:file_download_info type="mime" /></txp:file_download>))
      assert_equal "application/pdf", out
    end
  end

  test "if_plugin: no plugin is ever there; without a name it compares the Textpattern version" do
    # Haikai has no plugins, like a Textpattern site that has none installed.
    assert_equal "[no][yes][no]", render_txp(
      '[<txp:if_plugin name="abc_hi">yes<txp:else />no</txp:if_plugin>]' \
      '[<txp:if_plugin version="4.9">yes<txp:else />no</txp:if_plugin>]' \
      '[<txp:if_plugin version="99">yes<txp:else />no</txp:if_plugin>]'
    )
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
end
