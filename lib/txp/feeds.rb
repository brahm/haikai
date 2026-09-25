module Txp
  # RSS 2.0 and Atom 1.0 feeds: line-by-line ports of publish/rss.php and
  # publish/atom.php, including handle_lastmod() and RFC 3229 ("A-IM: feed")
  # instance manipulation.
  module Feeds
    NL = "\n".freeze
    TAB = "\t".freeze

    # The shared preamble of rss() and atom(): sections, categories, title.
    def feed_context
      area = Php.str(gps("area"))
      in_rss = @txp_sections.select { |_n, s| Php.truthy?(s["in_rss"]) }.keys
      sections = Php.do_list_unique(gps("section"))
      in_rss &= sections if sections.any? && in_rss.any?

      if Php.intval(get_pref("rss_how_many")).zero? || ((area == "" || area == "article") && in_rss.empty?)
        txp_die(gTxt("404_not_found"), "404")
      end

      section_titles = sections.map { |s| fetch_section_title(s) }
      categories = Php.do_list_unique(gps("category"))
      category_titles = categories.map { |c| fetch_category_title(c) }
      title = Php.str(get_pref("sitename"))
      title += " - #{section_titles.join(' - ')}" if sections.any?
      title += " - #{category_titles.join(' - ')}" if categories.any?
      [ area, sections, categories, title ]
    end

    def mail_or_domain
      if Php.truthy?(get_pref("use_mail_on_feeds_id"))
        entity_obfuscate(get_pref("blog_mail_uid"))
      else
        siteurl.split("/").first.to_s
      end
    end

    def feed_limit
      how_many = Php.intval(get_pref("rss_how_many"))
      limit = Php.truthy?(gps("limit")) ? Php.intval(gps("limit")) : how_many
      [ limit, [ 100, how_many ].max ].min
    end

    def feed_articles(sections, categories, limit)
      sfilter = sections.any? ? "AND Section IN (#{DB.quote_list(sections)})" : ""
      cfilter = categories.any? ? "AND (Category1 IN (#{DB.quote_list(categories)}) OR Category2 IN (#{DB.quote_list(categories)}))" : ""
      query = [ sfilter, cfilter ]
      front = filter_front_page("Section", [ "in_rss" ])
      query << front if Php.truthy?(front)
      feed_atts = Callbacks.fire("feed_filter")
      feed_atts = feed_atts.is_a?(Hash) ? feed_atts : (Php.truthy?(feed_atts) ? splat(Php.str(feed_atts).strip) : {})
      where = "#{filter_atts(feed_atts, true)['?']} #{query.join(' ')}"
      DB.rows("SELECT *, ID AS thisid, #{DB.timestamps('LastMod' => 'uLastMod', 'Posted' => 'uPosted', 'Expires' => 'uExpires')} " \
              "FROM textpattern WHERE #{where} ORDER BY uPosted DESC LIMIT #{limit}")
    end

    def feed_links(categories, limit)
      cfilter = categories.any? ? "category IN (#{DB.quote_list(categories)})" : "1"
      DB.rows("SELECT *, #{DB.timestamp('date', 'uDate')} FROM txp_link WHERE #{cfilter} ORDER BY date DESC, id DESC LIMIT #{limit}")
    end

    def comment_count_suffix(count)
      return "" unless Php.truthy?(get_pref("show_comment_count_in_feed"))

      Php.intval(count).positive? ? " [#{count}]" : ""
    end

    # escape_cdata()
    def cdata(str)
      "<![CDATA[#{Php.str(str).gsub(']]>', ']]]><![CDATA[]>')}]]>"
    end

    # replace_relative_urls()
    def absolutize(html, permalink = "")
      host = hu.sub(%r{/\z}, "")
      origin = host[%r{\Ahttps?://[^/]+}] || host
      html = Php.str(html)
      html = html.gsub(%r{(<a[^>]+href=")/(?!/)}) { "#{Regexp.last_match(1)}#{origin}/" }
      html = html.gsub(%r{(<img[^>]+src=")/(?!/)}) { "#{Regexp.last_match(1)}#{origin}/" }
      html = html.gsub(%r{(<a[^>]+href=")(?!\w+:|//)}) { "#{Regexp.last_match(1)}#{host}/" }
      html = html.gsub(%r{(<img[^>]+src=")(?!\w+:|//)}) { "#{Regexp.last_match(1)}#{host}/" }
      html = html.gsub(/href="#(.*)"/) { %(href="#{permalink}##{Regexp.last_match(1)}") } if Php.truthy?(permalink)
      html
    end

    def render_rss
      area, sections, categories, title = feed_context
      out = []
      out << tag("https://textpattern.com/?v=#{get_pref('version')}", "generator")
      out << tag(txpspecialchars(title), "title")
      out << tag(hu, "link")
      out << %(<atom:link href="#{pagelinkurl({ 'rss' => 1, 'area' => area, 'section' => sections, 'category' => categories, 'limit' => gps('limit') })}" rel="self" type="application/rss+xml" />)
      out << tag(txpspecialchars(get_pref("site_slogan")), "description")
      out << tag(safe_strftime("rss", DB.to_unix(get_pref("lastmod"))), "pubDate")
      out << Php.str(Callbacks.fire("rss_head"))

      articles = {}
      dates = {}
      limit = feed_limit

      if area == "" || area == "article"
        feed_articles(sections, categories, limit).each do |a|
          populate_article_data(a)
          art = @thisarticle
          cb = Php.str(Callbacks.fire("rss_entry"))
          permlink = permlinkurl(art)
          title = escape_title(CGI.unescapeHTML(Php.strip_tags(art["title"])).gsub(/&(?![#a-z0-9]+;)/i, "&amp;")) +
                  comment_count_suffix(art["comments_count"])
          summary = Php.str(parse(Php.str(art["excerpt"]))).strip
          content = ""
          if Php.truthy?(get_pref("syndicate_body_or_excerpt"))
            summary = Php.str(parse(Php.str(art["body"]))).strip if summary == ""
          else
            content = Php.str(parse(Php.str(art["body"]))).strip
          end

          item = +"#{NL}#{TAB}#{TAB}#{tag(title, 'title')}"
          item << "#{NL}#{TAB}#{TAB}#{tag(cdata(summary), 'description')}" if summary != ""
          item << "#{NL}#{TAB}#{TAB}#{tag("#{cdata(content)}#{NL}", 'content:encoded')}" if content != ""
          item << "#{NL}#{TAB}#{TAB}#{tag(permlink, 'link')}"
          item << "#{NL}#{TAB}#{TAB}#{tag(safe_strftime('rss', art['posted']), 'pubDate')}"
          item << "#{NL}#{TAB}#{TAB}#{tag(txpspecialchars(get_author_name(art['authorid'])), 'dc:creator')}"
          item << "#{NL}#{TAB}#{TAB}#{tag("tag:#{mail_or_domain},#{a['feed_time']}:#{get_pref('blog_uid')}/#{a['uid']}", 'guid', ' isPermaLink="false"')}#{NL}#{cb}"
          articles[art["thisid"]] = tag("#{absolutize(item, permlink)}#{TAB}", "item")
          dates[art["thisid"]] = art["modified"].to_i
        end
      elsif area == "link"
        feed_links(categories, limit).each do |a|
          item = +"#{NL}#{TAB}#{TAB}#{tag(txpspecialchars(a['linkname']), 'title')}"
          item << "#{NL}#{TAB}#{TAB}#{tag(txpspecialchars(a['description']), 'description')}" if Php.str(a["description"]).strip != ""
          item << "#{NL}#{TAB}#{TAB}#{tag(txpspecialchars(a['url']), 'link')}"
          item << "#{NL}#{TAB}#{TAB}#{tag(safe_strftime('rss', a['uDate']), 'pubDate')}#{NL}"
          articles[a["id"]] = tag("#{item}#{TAB}", "item")
          dates[a["id"]] = a["uDate"].to_i
        end
      end

      feed_empty_check(sections, categories, area) if articles.empty?
      articles = feed_instance_manipulation(articles, dates) unless articles.empty?
      out.concat(articles.values)

      namespaces = parse_ini_pairs(get_pref("feeds_namespaces"))
      { "dc" => "http://purl.org/dc/elements/1.1/", "content" => "http://purl.org/rss/1.0/modules/content/",
        "atom" => "http://www.w3.org/2005/Atom" }.each { |ns, url| namespaces[ns] ||= url }
      xmlns = namespaces.map { |ns, url| %( xmlns:#{ns}="#{url}") }.join

      @content_type = "application/rss+xml; charset=utf-8"
      %(<?xml version="1.0" encoding="UTF-8"?>#{NL}<rss version="2.0"#{xmlns}>#{NL}) +
        tag("#{NL}#{TAB}#{out.join("#{NL}#{TAB}")}#{NL}", "channel") + "#{NL}</rss>"
    end

    def render_atom
      area, sections, categories, title = feed_context
      pub = DB.row("SELECT RealName, email FROM txp_users WHERE privs = 1") || {}
      t_html = ' type="html"'
      out = []
      out << tag(txpspecialchars(title), "title", ' type="text"')
      out << tag(txpspecialchars(get_pref("site_slogan")), "subtitle", ' type="text"')
      out << %(<link rel="self" href="#{pagelinkurl({ 'atom' => 1, 'area' => area, 'section' => sections, 'category' => categories, 'limit' => gps('limit') })}" />)
      out << %(<link rel="alternate" type="text/html" href="#{hu}" />)
      feed_id = "tag:#{mail_or_domain},#{get_pref('blog_time_uid')}:#{get_pref('blog_uid')}"
      feed_id += "/#{sections.join(',')}" if sections.any?
      feed_id += "/#{categories.join(',')}" if categories.any?
      out << tag(feed_id, "id")
      out << tag("Textpattern", "generator", %( uri="https://textpattern.com/" version="#{get_pref('version')}"))
      out << tag(safe_strftime("w3cdtf", DB.to_unix(get_pref("lastmod"))), "updated")
      auth = [ tag(Php.str(pub["RealName"]), "name") ]
      auth << (Php.truthy?(get_pref("include_email_atom")) ? tag(entity_obfuscate(pub["email"]), "email") : "")
      auth << tag(hu, "uri")
      out << tag("#{NL}#{TAB}#{TAB}#{auth.join("#{NL}#{TAB}#{TAB}")}#{NL}#{TAB}", "author")
      out << Php.str(Callbacks.fire("atom_head"))

      articles = {}
      dates = {}
      limit = feed_limit

      if area == "" || area == "article"
        feed_articles(sections, categories, limit).each do |a|
          populate_article_data(a)
          art = @thisarticle
          cb = Php.str(Callbacks.fire("atom_entry"))
          count = comment_count_suffix(art["comments_count"])
          permlink = permlinkurl(art)
          e = []
          e << tag("#{NL}#{TAB}#{TAB}#{TAB}#{tag(txpspecialchars(get_author_name(art['authorid'])), 'name')}#{NL}#{TAB}#{TAB}", "author")
          e << tag(safe_strftime("w3cdtf", art["posted"]), "published")
          e << tag(safe_strftime("w3cdtf", art["modified"]), "updated")
          e << tag("#{txpspecialchars(art['title'])}#{count}", "title", t_html)
          e << %(<link rel="alternate" type="text/html" href="#{permlink}" />)
          e << tag("tag:#{mail_or_domain},#{a['feed_time']}:#{get_pref('blog_uid')}/#{a['uid']}", "id")
          e << (Php.str(art["category1"]).strip == "" ? "" : %(<category term="#{txpspecialchars(art['category1'])}" />))
          e << (Php.str(art["category2"]).strip == "" ? "" : %(<category term="#{txpspecialchars(art['category2'])}" />))

          summary = absolutize(parse(Php.str(art["excerpt"])), permlink).strip
          content = ""
          if Php.truthy?(get_pref("syndicate_body_or_excerpt"))
            summary = absolutize(parse(Php.str(art["body"])), permlink).strip if summary == ""
          else
            content = absolutize(parse(Php.str(art["body"])), permlink).strip
          end
          e << tag(cdata(content), "content", t_html) if content != ""
          e << tag(cdata(summary), "summary", t_html) if summary != ""

          articles[art["thisid"]] = tag("#{NL}#{TAB}#{TAB}#{e.join("#{NL}#{TAB}#{TAB}")}#{NL}#{TAB}#{cb}", "entry")
          dates[art["thisid"]] = art["modified"].to_i
        end
      elsif area == "link"
        feed_links(categories, limit).each do |a|
          # The "https?://" scheme is Textpattern's own (sic).
          url = Php.str(a["url"]).sub(%r{\A/(.*)}) { "https?://#{siteurl}/#{Regexp.last_match(1)}" }
          url = url.gsub(/&(.*?)=/) { "&amp;#{Regexp.last_match(1)}=" }
          e = []
          e << tag(txpspecialchars(a["linkname"]), "title", t_html)
          e << tag(cdata(a["description"]), "content", t_html)
          e << %(<link rel="alternate" type="text/html" href="#{url}" />)
          e << tag(safe_strftime("w3cdtf", a["uDate"]), "published")
          e << tag(safe_strftime("w3cdtf", a["uDate"]), "updated")
          e << tag("tag:#{mail_or_domain},#{safe_strftime('%Y-%m-%d', a['uDate'])}:#{get_pref('blog_uid')}/#{a['id']}", "id")
          articles[a["id"]] = tag("#{NL}#{TAB}#{TAB}#{e.join("#{NL}#{TAB}#{TAB}")}#{NL}#{TAB}", "entry")
          dates[a["id"]] = a["uDate"].to_i
        end
      end

      feed_empty_check(sections, categories, area) if articles.empty?
      articles = feed_instance_manipulation(articles, dates) unless articles.empty?
      out.concat(articles.values)

      @content_type = "application/atom+xml; charset=utf-8"
      %(<?xml version="1.0" encoding="UTF-8"?>#{NL}<feed xml:lang="#{Php.str(get_pref('language'))}" xmlns="http://www.w3.org/2005/Atom">#{NL}) +
        "#{TAB}#{out.join("#{NL}#{TAB}")}#{NL}</feed>"
    end

    # 404 for feeds of unknown sections or categories.
    def feed_empty_check(sections, categories, area)
      if sections.any?
        txp_die(gTxt("404_not_found"), "404") unless DB.field("SELECT name FROM txp_section WHERE name IN (#{DB.quote_list(sections)})")
      elsif categories.any?
        # (sic) Textpattern compares the link category list as a single name.
        where = area == "link" ? "name = #{q categories.join(',')} AND type = 'link'" : "name IN (#{DB.quote_list(categories)}) AND type = 'article'"
        txp_die(gTxt("404_not_found"), "404") unless DB.field("SELECT id FROM txp_category WHERE #{where}")
      end
    end

    # Last-Modified/ETag and RFC 3229 "A-IM: feed" handling for feeds.
    def feed_instance_manipulation(articles, dates)
      @response_headers["vary"] = "A-IM, If-None-Match, If-Modified-Since"
      handle_lastmod(dates.values.max)
      clfd = request_cache_timestamp
      a_im = @request&.headers&.[]("A-IM").to_s
      return articles unless a_im.index("feed").to_i.positive? && clfd.to_i.positive?

      kept = articles.reject { |id, _| dates[id] <= clfd }
      if kept.size < articles.size
        @response_headers["status"] = "226"
        @response_headers["cache-control"] = "IM"
        @response_headers["im"] = "feed"
      end
      kept
    end

    # Timestamp from If-Modified-Since or If-None-Match (a base-32 ETag).
    def request_cache_timestamp
      return nil unless @request

      if (hims = @request.headers["If-Modified-Since"])
        hims.to_s.empty? ? 0 : (Time.httpdate(hims.to_s).to_i rescue (Time.parse(hims.to_s).to_i rescue 0))
      elsif (hinm = @request.headers["If-None-Match"])
        tag = Php.trim_chars(hinm.to_s.strip, '"').split("-gzip").first.to_s
        tag.empty? ? 0 : tag.to_i(32)
      end
    end

    # get_lastmod()
    def get_lastmod(unix_ts = nil)
      unix_ts ||= DB.to_unix(get_pref("lastmod")).to_i
      newest = DB.field("SELECT #{DB.timestamp('Posted')} FROM textpattern WHERE Posted <= #{DB.now} AND Status >= 4 ORDER BY Posted DESC LIMIT 1")
      newest ? [ unix_ts, newest.to_i ].max : unix_ts
    end

    # handle_lastmod(): no caching outside live sites; otherwise sends
    # Last-Modified/ETag and raises Txp::NotModified for fresh conditional
    # requests.
    def handle_lastmod(unix_ts = nil)
      if production_status != "live"
        @response_headers["cache-control"] = "no-cache, no-store, max-age=0"
      elsif Php.truthy?(get_pref("send_lastmod"))
        unix_ts = [ get_lastmod(unix_ts), Time.now.to_i ].min
        @response_headers["last-modified"] = safe_strftime("rfc7231", unix_ts)
        @response_headers["etag"] = %("#{unix_ts.to_s(32)}")
        cached = request_cache_timestamp
        raise NotModified if cached && cached >= unix_ts
      end
    end

    def parse_ini_pairs(text)
      Php.str(text).each_line.with_object({}) do |line, out|
        next unless (m = line.match(/\A\s*([\w\-.]+)\s*=\s*"?(.*?)"?\s*\z/))

        out[m[1]] = m[2]
      end
    end
  end
end
