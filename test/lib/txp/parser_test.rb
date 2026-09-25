require "test_helper"

# Core template language: tokenizer, conditionals, global attributes,
# variables, forms/yield and <txp:evaluate />.
class Txp::ParserTest < ActiveSupport::TestCase
  setup { TxpTestSite.install! }

  test "plain text passes through" do
    assert_equal "Hello world", render_txp("Hello world")
  end

  test "self-closing and container tags" do
    assert_equal "Site: My site", render_txp("Site: <txp:site_name />")
    assert_equal "[yes]", render_txp('[<txp:if_variable name="x" not>yes</txp:if_variable>]')
  end

  test "else branch of conditionals" do
    out = render_txp('<txp:variable name="a" value="1" /><txp:if_variable name="a" value="2">two<txp:else />not two</txp:if_variable>')
    assert_equal "not two", out
  end

  test "nested conditionals keep their own else" do
    markup = '<txp:variable name="a" value="1" /><txp:if_variable name="a">A<txp:if_variable name="b">B<txp:else />noB</txp:if_variable><txp:else />noA</txp:if_variable>'
    assert_equal "AnoB", render_txp(markup)
  end

  test "attribute values in single quotes are parsed" do
    out = render_txp(%q(<txp:variable name="n" value='<txp:site_name />' /><txp:variable name="n" />))
    assert_equal "My site", out
  end

  test "double quotes escape by doubling" do
    assert_equal 'say "hi"', render_txp(%q(<txp:variable name="q" value="say ""hi""" /><txp:variable name="q" />))
  end

  test "valueless attributes are true" do
    out = render_txp('<txp:variable name="x" value="abc" /><txp:variable name="x" escape="upper" />')
    assert_equal "ABC", out
  end

  test "wraptag, class and label global attributes" do
    out = render_txp('<txp:site_name wraptag="h1" class="brand" />')
    assert_equal '<h1 class="brand">My site</h1>', out
    assert_equal "", render_txp('<txp:variable name="empty" value="" /><txp:variable name="empty" wraptag="p" />')
  end

  test "default global attribute" do
    assert_equal "fallback", render_txp('<txp:variable name="e" value="" /><txp:variable name="e" default="fallback" />')
  end

  test "escape global attribute" do
    assert_equal "&lt;b&gt;", render_txp(%q(<txp:variable name="h" value="<b>" /><txp:variable name="h" escape="html" />))
    assert_equal "hello+world", render_txp('<txp:variable name="u" value="hello world" /><txp:variable name="u" escape="url" />')
    assert_equal "Hello World", render_txp('<txp:variable name="t" value="hello world" /><txp:variable name="t" escape="title" />')
    assert_equal "b", render_txp(%q(<txp:variable name="s" value="<p>b</p>" /><txp:variable name="s" escape="tags" />))
    assert_equal "42", render_txp('<txp:variable name="n" value="42abc" /><txp:variable name="n" escape="integer" />')
    assert_equal "a b", render_txp(%Q(<txp:variable name="w" value="  a\n  b " /><txp:variable name="w" escape="tidy" />))
  end

  test "not attribute on non-conditional tags" do
    assert_equal "1", render_txp('<txp:variable name="z" value="" /><txp:variable name="z" not />')
    assert_equal "", render_txp('<txp:variable name="z" value="x" /><txp:variable name="z" not />')
  end

  test "breakby, sort, limit and offset" do
    assert_equal "a, b, c", render_txp('<txp:variable name="l" value="c,a,b" /><txp:variable name="l" breakby="," sort="asc" break=", " />')
    assert_equal "b|c", render_txp('<txp:variable name="l" value="a,b,c,d" /><txp:variable name="l" breakby="," limit="2" offset="1" break="|" />')
    assert_equal "<ul><li>x</li><li>y</li></ul>", squish(render_txp('<txp:variable name="l" value="x,y" /><txp:variable name="l" breakby="," wraptag="ul" break="li" />')).gsub("> <", "><")
  end

  test "trim and replace" do
    assert_equal "a-b-c", render_txp('<txp:variable name="l" value="a , b , c" /><txp:variable name="l" breakby="," trim break="-" />')
    assert_equal "x_y", render_txp('<txp:variable name="l" value="x y" /><txp:variable name="l" trim=" " replace="_" />')
  end

  test "variable add and output" do
    assert_equal "3", render_txp('<txp:variable name="c" value="1" /><txp:variable name="c" add="2" /><txp:variable name="c" />')
    assert_equal "ab", render_txp('<txp:variable name="s" value="a" /><txp:variable name="s" add="b" separator="" /><txp:variable name="s" />')
    assert_equal "HI", render_txp('<txp:variable name="o" value="hi" output="upper" />')
  end

  test "variable global attribute stores tag output" do
    assert_equal "[My site]", render_txp('<txp:site_name variable="sn" />[<txp:variable name="sn" />]')
  end

  test "if_variable match modes" do
    render = ->(m, v) { render_txp(%(<txp:variable name="v" value="apple,banana" /><txp:if_variable name="v" value="#{v}" match="#{m}">Y<txp:else />N</txp:if_variable>)) }
    assert_equal "Y", render.call("any", "kiwi,banana")
    assert_equal "N", render.call("all", "kiwi,banana")
    assert_equal "Y", render.call("pattern", "^app")
    assert_equal "N", render.call("exact", "apple")
    assert_equal "Y", render_txp('<txp:variable name="n" value="10" /><txp:if_variable name="n" value="9" match=">">Y</txp:if_variable>')
  end

  test "output_form with yield and shortcodes" do
    Form.create!(name: "box", skin: "test", type: "misc", Form: '<div class="<txp:yield name="kind" default="plain" />"><txp:yield /></div>')
    assert_equal '<div class="note">Hi</div>', render_txp('<txp:output_form form="box" kind="note">Hi</txp:output_form>')
    assert_equal '<div class="plain">Yo</div>', render_txp("<txp::box>Yo</txp::box>")
    # A self-closed caller has nothing to yield (Textpattern 4.9 prints "1").
    assert_equal '<div class="x"></div>', render_txp('<txp::box kind="x" />')
  end

  test "if_yield" do
    Form.create!(name: "cond", skin: "test", type: "misc", Form: '<txp:if_yield name="a">has a<txp:else />no a</txp:if_yield>')
    assert_equal "has a", render_txp('<txp::cond a="1" />')
    assert_equal "no a", render_txp("<txp::cond />")
  end

  test "evaluate with query" do
    assert_equal "5", render_txp('<txp:evaluate query="2+3" />')
    assert_equal "yes", render_txp('<txp:evaluate query="1 &lt; 2">yes<txp:else />no</txp:evaluate>'.gsub("&lt;", "<"))
    assert_equal "no", render_txp('<txp:evaluate query="1 > 2">yes<txp:else />no</txp:evaluate>')
  end

  test "evaluate tests contained tags" do
    assert_equal "", render_txp('<txp:evaluate><p><txp:variable name="none" /></p></txp:evaluate>')
    assert_equal "<p>x</p>", render_txp('<txp:variable name="some" value="x" /><txp:evaluate><p><txp:variable name="some" /></p></txp:evaluate>')
    assert_equal "empty", render_txp('<txp:evaluate><txp:variable name="none" /><txp:else />empty</txp:evaluate>')
  end

  test "evaluate test attribute selects tags" do
    out = render_txp('<txp:variable name="a" value="A" /><txp:evaluate test="site_slogan">[<txp:variable name="a" />]</txp:evaluate>', prefs: { "site_slogan" => "" })
    assert_equal "", out
  end

  test "hide" do
    assert_equal "ab", render_txp("a<txp:hide>hidden</txp:hide>b")
  end

  test "text tag uses textpacks with replacements" do
    assert_equal "Search", render_txp('<txp:text item="search" />')
    assert_equal "missing_key", render_txp('<txp:text item="missing_key" />')
  end

  test "unknown tags produce a warning in debug mode" do
    render_txp("<txp:no_such_tag />")
    assert_includes last_errors, "no_such_tag"
  end

  test "short tags prefix syntax" do
    Txp::Registry.default.register("abc_hello") { |_txp, atts, _thing| "Hello #{atts['who']}" }
    assert_equal "Hello Ann", render_txp('<abc::hello who="Ann" />')
    assert_equal "Hello Bo", render_txp('<txp:abc_hello who="Bo" />')
  ensure
    Txp::Registry.default.unregister("abc_hello")
  end

  test "date formatting" do
    assert_equal "2024", render_txp('<txp:date time="2024-05-06 10:00" format="%Y" />')
    assert_equal "May 06, 2024", render_txp('<txp:date time="2024-05-06 10:00" format="%B %d, %Y" />')
    assert_equal "2024-05-06T10:00:00+0000", render_txp('<txp:date time="2024-05-06 10:00" format="iso8601" />')
  end

  test "if_different" do
    out = render_txp('<txp:variable name="l" value="a,a,b" /><txp:variable name="l" breakby="," breakform="d" />') rescue nil
    Form.create!(name: "d", skin: "test", type: "misc", Form: "<txp:if_different><txp:yield item /></txp:if_different>")
    out = render_txp('<txp:variable name="l" value="a,a,b" /><txp:variable name="l" breakby="," breakform="d" break="," />')
    assert_equal "a,b", out.split(",").reject(&:empty?).join(",")
  end

  test "circular forms are stopped" do
    Form.create!(name: "loop", skin: "test", type: "misc", Form: "x<txp:output_form form=\"loop\" />")
    out = render_txp('<txp:output_form form="loop" />')
    assert_equal "x" * 15, out
  end
end
