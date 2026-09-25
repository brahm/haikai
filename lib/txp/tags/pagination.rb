module Txp
  module Tags
    # <txp:newer />, <txp:older /> and <txp:pages /> (port of
    # \Textpattern\Tag\Syntax\Pagination::pager).
    module Pagination
      def tag_pager(atts, thing = nil, newer = nil)
        @pager ||= { pg: true, num_pages: nil, linkall: nil, top: 1, shown: {} }
        st = @pager
        get = atts.key?("total") && atts["total"] == true
        set = newer.nil? && (atts.key?("pg") || (atts.key?("total") && !get))
        put = get || !set || atts.key?("break")
        pairs = {}
        pairs["total"] = true if get

        if put
          pairs.merge!(
            "shift" => false, "showalways" => false,
            "link" => st[:linkall].nil? ? (newer.nil? || !thing.nil? ? false : "") : st[:linkall],
            "title" => "", "escape" => "html", "rel" => "", "limit" => 0, "wraptag" => "", "break" => "",
            "class" => "", "html_id" => ""
          )
        end

        if set
          store = st.dup
          pairs.merge!("pg" => st[:pg], "total" => st[:num_pages], "shift" => 1, "showalways" => 2, "link" => false)
        end

        a = lAtts(pairs, atts)
        pg = a.key?("pg") ? a["pg"] : st[:pg]

        if set
          total = a["total"]
          if !total.nil? && total != true
            t, by = "#{total}/0".split("/")
            by = by.to_i
            st[:num_pages] = by.positive? ? (t.to_f / by).ceil : t.to_i
          elsif pg == true
            st[:num_pages] = @thispage && @thispage["numPages"] ? @thispage["numPages"].to_i : nil
          end
          st[:pg] = pg
        end

        if st[:num_pages].nil?
          if @thispage && @thispage["numPages"]
            st[:num_pages] = @thispage["numPages"].to_i
          else
            return @is_article_list ? postpone_process(2) : ""
          end
        end

        num_pages = st[:num_pages]
        shift = a["shift"]

        if set
          st[:shown] = {}
          st[:linkall] = a["link"]

          unless put
            st[:top] = if shift == true
              0
            else
              Php.intval(shift).negative? ? num_pages + Php.intval(shift) + 1 : Php.intval(shift)
            end

            unless thing.nil?
              thing = parse(thing, num_pages >= (Php.truthy?(a["showalways"]) ? Php.intval(a["showalways"]) : 2))
              @pager = store
            end

            return thing
          end
          shift = true if shift == false
        end

        pgc = pg == true ? "pg" : Php.str(pg)
        thispg = pg == true && @thispage && @thispage["pg"] ? Php.intval(@thispage["pg"]) : Php.intval(gps(pgc, st[:top]))
        thepg = [ [ thispg, num_pages ].min, 1 ].max
        range = nil

        if get
          if thing.nil? && shift == false
            return newer.nil? ? num_pages : (newer ? thepg - 1 : num_pages - thepg)
          elsif shift == true || shift == false
            range = newer ? thepg - 1 : num_pages - thepg unless newer.nil?
          else
            range = Php.intval(shift)
          end
        end

        if !range.nil? && range != false
          pages = if range.zero?
            []
          elsif range.positive?
            if newer.nil?
              (-[ range, 2 * range + thepg - num_pages ].max..[ range, 2 * range - thepg + 1 ].max).to_a
            elsif newer
              [ range, 2 * range + thepg - num_pages ].max.downto(1).to_a
            else
              (1..[ range, 2 * range - thepg + 1 ].max).to_a
            end
          elsif !newer.nil?
            if newer
              (-1).downto(-[ -range, -2 * range + thepg - num_pages ].max).to_a
            else
              (-[ -range, -2 * range - thepg + 1 ].max..-1).to_a
            end
          else
            lo = [ [ 1 - range - thepg, 1 - 2 * range - num_pages ].max, 0 ].min
            hi = [ 0, [ num_pages + range - thepg, num_pages + 2 * range - 1 ].min ].max
            (lo..hi).to_a
          end
        elsif shift == true || shift == false
          pages = if newer.nil?
            shift ? ((1 - thepg)..(num_pages - thepg)).to_a : [ 0 ]
          else
            [ shift ? true : 1 ]
          end
          range = !shift
        else
          pages = Php.do_list(shift, [ ",", "-" ]).map(&:to_i)
          range = false
        end

        saved_items = %w[page total url].to_h { |k| [ k, @txp_item[k] ] }
        out = []
        @txp_item = @txp_item.merge("total" => num_pages)
        limit = Php.truthy?(a["limit"]) ? Php.intval(a["limit"]) : -1
        old_context = @txp_context
        @txp_context = (@txp_context || {}).merge(get_context(@txp_context.nil? || @txp_context.empty? ? true : nil)) { |_k, old, _new| old }
        class_att = a["wraptag"] == "" && a["class"] != "" ? %( class="#{txpspecialchars(a['class'])}") : ""
        id_att = a["wraptag"] == "" && a["html_id"] != "" ? %( id="#{txpspecialchars(a['html_id'])}") : ""
        title = a["title"]
        title_att = if title != ""
          val = a["escape"] == "html" ? escape_title(title) : (Php.truthy?(a["escape"]) ? txp_escape(a["escape"], title) : title)
          %( title="#{val}")
        else
          ""
        end

        pages.each do |page|
          nextpg = if newer.nil?
            thepg + page
          elsif newer
            page == true ? 1 : (page.to_i.negative? ? -page : thepg - page)
          else
            page == true ? num_pages : (page.to_i.negative? ? num_pages + page + 1 : thepg + page)
          end

          min = newer == false && range != false ? thepg + 1 : 1
          max = newer == true && range != false ? thepg - 1 : num_pages

          if nextpg >= min && nextpg <= max
            if !st[:shown][nextpg] || Php.truthy?(a["showalways"])
              @txp_context[pgc] = nextpg == st[:top] ? nil : nextpg
              url = pagelinkurl(@txp_context)
              @txp_item["page"] = nextpg
              @txp_item["url"] = url

              if shift != false || newer.nil? || !(range == true || range == false)
                st[:shown][nextpg] = true
                limit -= 1
              end

              item = thing.nil? ? (newer.nil? ? nextpg.to_s : url) : Php.str(parse(thing))
              rel = a["rel"]
              rel_att = if rel == true
                nextpg == thepg + 1 ? ' rel="next"' : (nextpg == thepg - 1 ? ' rel="prev"' : "")
              elsif Php.str(rel) == ""
                ""
              else
                %( rel="#{txpspecialchars(rel)}")
              end
              link = a["link"]
              url = if Php.truthy?(link) || (link == false && nextpg != thispg)
                href(item, url, "#{id_att}#{title_att}#{rel_att}#{class_att}")
              else
                item
              end
            else
              url = false
            end
          else
            url = thing.nil? ? false : parse(thing, Php.truthy?(a["showalways"]))
          end

          out << url unless Php.empty?(url)
          break if limit.zero?
        end

        saved_items.each { |k, v| v.nil? ? @txp_item.delete(k) : @txp_item[k] = v }
        @txp_context = old_context

        if a["wraptag"] != ""
          do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"], "html_id" => a["html_id"] })
        else
          do_wrap(out, "", a["break"])
        end
      end
    end
  end
end
