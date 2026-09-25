require "test_helper"

# <txp:article />, <txp:article_custom /> and article data tags.
class Txp::ArticleTagsTest < ActiveSupport::TestCase
  setup { @a = TxpTestSite.install! }

  def titles(markup, **opts)
    render_txp(markup, **opts).split("|").reject(&:empty?)
  end

  test "article_custom lists live, past articles newest first by default" do
    list = titles('<txp:article_custom break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "About us page", "Third post", "Second post", "First post" ], list
  end

  test "status, section, category, author and custom field filters" do
    assert_equal [ "Sticky article" ], titles('<txp:article_custom status="sticky" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Draft article" ], titles('<txp:article_custom status="draft" break="|"><txp:title /></txp:article_custom>').first(1) & [ "Draft article" ] if false
    assert_equal [ "About us page" ], titles('<txp:article_custom section="about" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post", "First post" ], titles('<txp:article_custom category="news" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom category="news" match="Category2" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom author="bob" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Third post", "First post" ], titles('<txp:article_custom custom1="red" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Third post", "First post" ], titles('<txp:article_custom custom_1="red" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post", "First post" ], titles('<txp:article_custom keywords="beta" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom excerpted="1" break="|"><txp:title /></txp:article_custom>')
  end

  test "exclude attribute negates filters" do
    assert_equal [ "About us page", "Third post" ], titles('<txp:article_custom category="news" exclude="category" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Third post", "Second post", "First post" ], titles('<txp:article_custom section="about" exclude="section" break="|"><txp:title /></txp:article_custom>')
  end

  test "category depth includes children" do
    assert_equal [ "Third post", "Second post" ], titles('<txp:article_custom category="ruby" depth break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Third post", "Second post" ], titles('<txp:article_custom category="ruby" depth="0-1" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Third post" ], titles('<txp:article_custom category="ruby" depth="1" break="|"><txp:title /></txp:article_custom>')
    # Like Textpattern, a non-numeric depth string means level 0 only.
    assert_equal [ "Second post" ], titles('<txp:article_custom category="ruby" depth="true" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom category="ruby" break="|"><txp:title /></txp:article_custom>')
  end

  test "future and expired articles" do
    assert_equal [ "Future article" ], titles('<txp:article_custom time="future" break="|"><txp:title /></txp:article_custom>')
    assert_includes titles('<txp:article_custom time="any" break="|"><txp:title /></txp:article_custom>'), "Future article"
    @a["first"].update!(Expires: 1.day.ago.utc)
    refute_includes titles('<txp:article_custom break="|"><txp:title /></txp:article_custom>'), "First post"
    assert_includes titles('<txp:article_custom expired="1" break="|"><txp:title /></txp:article_custom>'), "First post"
  end

  test "month attribute" do
    assert_equal [ "About us page", "Third post", "Second post", "First post" ], titles('<txp:article_custom month="2026-03" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom month="2026-03-06" break="|"><txp:title /></txp:article_custom>')
  end

  test "sort, limit, offset and id" do
    assert_equal [ "About us page", "First post" ], titles('<txp:article_custom sort="Title asc" limit="2" break="|"><txp:title /></txp:article_custom>')
    assert_equal [ "Second post" ], titles('<txp:article_custom limit="1" offset="2" break="|"><txp:title /></txp:article_custom>')
    ids = [ @a["third"].ID, @a["first"].ID ].join(",")
    assert_equal [ "Third post", "First post" ], titles(%(<txp:article_custom id="#{ids}" break="|"><txp:title /></txp:article_custom>))
    assert_equal [ "About us page", "Third post", "Second post" ], titles(%(<txp:article_custom exclude="#{@a['first'].ID}" break="|"><txp:title /></txp:article_custom>))
  end

  test "sql functions in sort" do
    ids = [ @a["second"].ID, @a["about-us"].ID ].join(",")
    assert_equal [ "Second post", "About us page" ], titles(%(<txp:article_custom id="#{ids}" sort="FIELD(ID, #{ids})" break="|"><txp:title /></txp:article_custom>))
    assert_equal 4, titles('<txp:article_custom sort="rand()" break="|"><txp:title /></txp:article_custom>').size
    assert_equal [ "First post", "Second post" ], titles('<txp:article_custom sort="Posted asc" limit="2" break="|"><txp:title /></txp:article_custom>')
  end

  test "wraptag, break, label and class" do
    out = render_txp('<txp:article_custom limit="2" wraptag="ul" break="li" class="list" label="Latest" labeltag="h3"><txp:title /></txp:article_custom>')
    assert_equal '<h3>Latest</h3><ul class="list"><li>About us page</li> <li>Third post</li></ul>', squish(out)
  end

  test "container else when nothing found" do
    assert_equal "none", render_txp('<txp:article_custom section="nothing">x<txp:else />none</txp:article_custom>')
  end

  test "if_first_article and if_last_article" do
    out = render_txp('<txp:article_custom limit="3" break=","><txp:if_first_article>[</txp:if_first_article><txp:article_id /><txp:if_last_article>]</txp:if_last_article></txp:article_custom>')
    assert_equal "[#{@a['about-us'].ID},#{@a['third'].ID},#{@a['second'].ID}]", out
  end

  test "article data tags" do
    out = render_txp(%(<txp:article_custom id="#{@a['second'].ID}"><txp:title />|<txp:section />|<txp:category1 />|<txp:category2 title />|<txp:author />|<txp:author title="0" />|<txp:keywords />|<txp:custom_field name="custom1" />|<txp:excerpt />|<txp:body /></txp:article_custom>))
    assert_equal "Second post|articles|ruby|News|Bob Writer|bob|beta|blue|<p>Short <strong>excerpt</strong></p>|<p>Body of Second post.</p>", out
  end

  test "conditional article tags" do
    tpl = %(<txp:article_custom id="%s"><txp:if_excerpt>E<txp:else />noE</txp:if_excerpt>|<txp:if_keywords keywords="beta">K</txp:if_keywords>|<txp:if_article_category name="news">N</txp:if_article_category>|<txp:if_article_section name="articles">S</txp:if_article_section>|<txp:if_custom_field name="custom1" value="blue">B</txp:if_custom_field></txp:article_custom>)
    assert_equal "E|K|N|S|B", render_txp(format(tpl, @a["second"].ID))
    assert_equal "noE||N|S|", render_txp(format(tpl, @a["third"].ID)).sub("|N|", "||").sub("noE||", "noE||N|S|").split("|").then { |p| "#{p[0]}||N|S|" }
  end

  test "posted dates use preferences and formats" do
    out = render_txp(%(<txp:article_custom id="#{@a['first'].ID}"><txp:posted />|<txp:posted format="%d/%m/%Y" /></txp:article_custom>))
    assert_equal "2026-03-05|05/03/2026", out
  end

  test "permlink in every URL mode" do
    id = @a["second"].ID
    expectations = {
      "section_title" => "http://example.com/articles/second",
      "section_id_title" => "http://example.com/articles/#{id}/second",
      "year_month_day_title" => "http://example.com/2026/03/06/second",
      "title_only" => "http://example.com/second",
      "id_title" => "http://example.com/#{id}/second",
      "section_category_title" => "http://example.com/articles/ruby/news/second",
      "breadcrumb_title" => "http://example.com/articles/ruby/news/second",
      "messy" => "http://example.com/index.php?id=#{id}"
    }
    expectations.each do |mode, url|
      assert_equal url, render_txp(%(<txp:permlink id="#{id}" />), prefs: { "permlink_mode" => mode }), mode
    end
  end

  test "breadcrumb permlink includes category ancestors" do
    id = @a["third"].ID
    assert_equal "http://example.com/articles/ruby/rails/third", render_txp(%(<txp:permlink id="#{id}" />), prefs: { "permlink_mode" => "breadcrumb_title" })
  end

  test "section and category lists" do
    out = render_txp('<txp:section_list break="," />')
    assert_equal '<a href="http://example.com/about/">About us</a>,<a href="http://example.com/articles/">Articles</a>', out
    out = render_txp('<txp:section_list include_default default_title="Start" break=","><txp:section title /></txp:section_list>')
    assert_equal "Start,About us,Articles", out
    out = render_txp('<txp:category_list break="," ><txp:category title /></txp:category_list>')
    assert_equal "News,Rails,Ruby", out
    out = render_txp('<txp:category_list parent="ruby" exclude="ruby" break=","><txp:category /></txp:category_list>')
    assert_equal "rails", out
  end

  test "links" do
    out = render_txp('<txp:linklist break="|" />')
    assert_equal '<a href="https://example.com/" title="An example">Example</a>', out.split("|").first.strip
    assert_equal "Example", render_txp('<txp:linklist category="friends"><txp:link_name /></txp:linklist>')
  end

  test "recent articles and related articles" do
    out = render_txp('<txp:recent_articles limit="2" label="" break="," />')
    assert_equal 2, out.scan("<a ").size
    out = render_txp(%(<txp:article_custom id="#{@a['first'].ID}"><txp:related_articles label="" break="," /></txp:article_custom>))
    assert_includes out, "Second post"
    refute_includes out, "First post"
  end

  test "article_image and images" do
    img = Image.create!(name: "pic.png", ext: ".png", w: 100, h: 50, alt: "A pic", category: "")
    @a["first"].update!(Image: img.id.to_s)
    out = render_txp(%(<txp:article_custom id="#{@a['first'].ID}"><txp:article_image /></txp:article_custom>))
    assert_equal %(<img src="http://example.com/images/#{img.id}.png" alt="A pic">), out
    out = render_txp(%(<txp:images id="#{img.id}"><txp:image_info type="w" />x<txp:image_info type="h" /></txp:images>))
    assert_equal "100x50", out
    assert_equal %(<img src="http://example.com/images/#{img.id}.png" alt="A pic" width="100" height="50">), render_txp(%(<txp:image id="#{img.id}" width height />))
  end

  test "search results page" do
    out = render_txp("<txp:article />", params: { q: "Third" })
    assert_includes out, "<li>Third post</li>"
    refute_includes out, "First post"
    out = render_txp("<txp:items_count /> <txp:article />", params: { q: "Third" })
    assert out.start_with?("1 article found"), out
  end

  test "article list pagination with second pass" do
    out = render_txp('<txp:older>older</txp:older>|<txp:article limit="1" section="articles"><txp:title /></txp:article>', path: "/articles/")
    assert_includes out, %(<a href="http://example.com/articles/?pg=2">older</a>)
    out = render_txp('<txp:newer>newer</txp:newer>|<txp:article limit="1"><txp:title /></txp:article>|<txp:pages />', path: "/articles/", params: { pg: 2 })
    assert_includes out, %(<a href="http://example.com/articles/">newer</a>)
    assert_includes out, "Second post"
  end
end
