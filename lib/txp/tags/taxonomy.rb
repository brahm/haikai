module Txp
  module Tags
    # Section and category tags.
    module Taxonomy
      def tag_category(atts, thing = nil)
        a = lAtts({
          "class" => "", "link" => !thing.nil?, "name" => "", "parent" => 0, "section" => nil,
          "this_section" => 0, "title" => 0, "type" => "article", "url" => 0, "rel" => false,
          "escape" => true, "wraptag" => ""
        }, atts)
        c = Php.str(@pretext["c"])
        context = @pretext["context"]

        if Php.truthy?(a["name"])
          category = a["name"] == true ? c : Php.str(a["name"])
          type = a["type"] == true ? context : valid_context(a["type"])
        elsif @thiscategory.nil? || @thiscategory.empty?
          category = c
          type = context
        else
          category = @thiscategory["name"]
          type = @thiscategory["type"] || context
        end

        parent = Php.intval(a["parent"])
        if Php.truthy?(category) && parent != 0
          path = get_root_path(category, type).map { |r| r["name"] }
          parent = path.length + parent if parent.negative?
          category = path[parent] || false
        end

        out = false
        old = @thiscategory

        if Php.truthy?(category) && (@thiscategory.nil? || @thiscategory.empty? || @thiscategory["name"] != category || @thiscategory["type"] != type)
          @thiscategory = ck_cat(type, category) || nil
          category = Php.truthy?(@thiscategory) ? @thiscategory["name"] : false
        end

        if Php.truthy?(category)
          section = a["section"]
          if Php.truthy?(a["this_section"]) || section == true
            section = @pretext["s"] == "default" ? "" : @pretext["s"]
          elsif section.nil?
            section = @thiscategory && @thiscategory.key?("section") ? @thiscategory["section"] : false
          end

          label = Php.truthy?(a["title"]) ? fetch_category_title(category, type) : category
          url = pagelinkurl({ "s" => type == "article" ? section : false, "c" => category, "context" => type })
          klass = Php.truthy?(a["class"]) && Php.empty?(a["wraptag"]) ? a["class"] : false
          escape = a["escape"]

          out = if Php.truthy?(thing)
            if Php.truthy?(a["link"])
              href(parse(thing), url, { "class" => klass, "title" => Php.truthy?(a["title"]) ? label : false, "rel" => Php.truthy?(a["rel"]) ? a["rel"] : false })
            else
              parse(thing)
            end
          elsif Php.truthy?(a["link"])
            href(Php.truthy?(escape) ? txp_escape(escape, label) : label, url, { "class" => klass, "rel" => Php.truthy?(a["rel"]) ? a["rel"] : false })
          elsif Php.truthy?(a["url"])
            url
          else
            Php.truthy?(escape) ? txp_escape(escape, label) : label
          end
        end

        @thiscategory = old
        out != false ? do_tag(out, a["wraptag"], a["class"]) : (Php.truthy?(thing) ? parse(thing, false) : nil)
      end

      def tag_category_list(atts, thing = nil)
        a = lAtts({
          "active_class" => "", "break" => "br", "categories" => nil,
          "children" => atts.key?("categories") ? (Php.empty?(atts["parent"]) ? 0 : true) : 1,
          "class" => "category_list", "exclude" => "", "form" => "", "html_id" => "", "label" => "",
          "labeltag" => "", "limit" => "", "link" => "1", "offset" => "", "parent" => "", "section" => "",
          "sort" => atts.key?("categories") ? "" : (Php.empty?(atts["parent"]) ? "name" : "lft"),
          "this_section" => 0, "type" => "article", "wraptag" => ""
        }, atts)
        c = Php.str(@pretext["c"])
        categories = a["categories"]
        parent = a["parent"]
        current = @thiscategory && @thiscategory["name"] ? @thiscategory["name"] : (c != "" ? c : "root")
        categories = current if categories == true
        parent = current if parent == true
        children = a["children"]

        cats = if children.is_a?(Hash)
          children
        else
          get_tree(atts.merge("categories" => categories, "parent" => parent, "children" => children, "sort" => a["sort"], "flatten" => false))
        end
        section = Php.truthy?(a["this_section"]) ? (@pretext["s"] == "default" ? "" : @pretext["s"]) : a["section"]
        old = @thiscategory
        out = []
        count = 0
        last = cats.length
        active_class = txpspecialchars(a["active_class"])
        type = a["type"]

        cats.each do |name, cat|
          count += 1
          nodes = if cat["children"].is_a?(Hash) && cat["children"].any?
            Php.str(process_tags("category_list", { "label" => "", "html_id" => "", "children" => cat["children"] }.merge(atts.except("label", "html_id", "children")), thing))
          else
            ""
          end
          @thiscategory = cat.except("children")

          if thing.nil? && Php.empty?(a["form"])
            item = if Php.truthy?(a["link"])
              klass = Php.truthy?(active_class) && c.casecmp?(name) ? %( class="#{active_class}") : ""
              tag(txpspecialchars(@thiscategory["title"]), "a", "#{klass} href=\"#{pagelinkurl({ 's' => section, 'c' => name, 'context' => type })}\"")
            else
              name
            end
          else
            @thiscategory["type"] = type
            @thiscategory["is_first"] = count == 1
            @thiscategory["is_last"] = count == last
            @thiscategory["section"] = section if atts.key?("section")
            item = Php.str(Php.truthy?(a["form"]) ? parse_form(a["form"]) : parse(thing))
          end

          numeric_children = Php.numeric?(children) && Php.intval(children) <= 1
          out << (numeric_children || !item.include?("<+>") ? item + nodes : item.gsub("<+>", nodes))
        end

        @thiscategory = old
        if out.any?
          (Php.truthy?(a["label"]) ? do_label(a["label"], a["labeltag"]) : "") +
            do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"], "html_id" => a["html_id"] })
        else
          Php.truthy?(thing) ? parse(thing, false) : ""
        end
      end

      def tag_if_category(atts, thing = nil)
        a = lAtts({ "category" => atts.key?("level"), "type" => false, "name" => false, "parent" => 0, "level" => nil }, atts)
        c = Php.str(@pretext["c"])
        context = @pretext["context"]
        category = a["category"]
        type = a["type"]
        name = a["name"]
        parent = a["parent"]

        if category == false
          category = c
          the_type = context
        elsif category == true
          category = @thiscategory.nil? || Php.empty?(@thiscategory["name"]) ? c : @thiscategory["name"]
          the_type = @thiscategory.nil? || Php.empty?(@thiscategory["type"]) ? context : @thiscategory["type"]
        else
          the_type = Php.truthy?(type) && type != true ? valid_context(type) : context
          parent = true unless Php.truthy?(parent) || type == false
          category = Php.str(category).strip
        end

        if Php.truthy?(type) && type != true && the_type != type
          x = false
        else
          parentname = Php.truthy?(parent) && Php.numeric?(Php.str(parent))
          x = name == false ? Php.truthy?(category) : (parentname || Php.in_list(category, name))
        end

        if x && !a["level"].nil?
          lvl = @thiscategory ? @thiscategory["level"] : nil
          x = Php.empty?(lvl) ? Php.empty?(a["level"]) : Php.loose_eq(lvl, a["level"])
        end

        if x && Php.truthy?(parent) && Php.truthy?(category)
          path = get_root_path(category, the_type).map { |r| r["name"] }
          unless parentname
            name = parent
            parent = true
          end
          names = Php.do_list_unique(name == false ? "" : name)

          if parent == true
            x = path.length > 1 && (name == false || (path & names).any?)
          else
            p = Php.intval(parent)
            p = path.length + p if p.negative?
            x = !path[p].nil? && (name == false || names.include?(path[p]))
          end
        end

        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_category(atts, thing = nil)
        a = lAtts({ "name" => "", "number" => "" }, atts)
        cats = []
        if Php.truthy?(a["number"])
          v = @thisarticle && @thisarticle["category#{a['number']}"]
          cats = [ v ] if Php.truthy?(v)
        else
          cats << @thisarticle["category1"] if @thisarticle && Php.truthy?(@thisarticle["category1"])
          cats << @thisarticle["category2"] if @thisarticle && Php.truthy?(@thisarticle["category2"])
          cats.uniq!
        end
        cats = Php.do_list(a["name"]) & cats if Php.truthy?(a["name"])
        x = cats.any?
        thing.nil? ? x : parse(thing, x)
      end

      def tag_section(atts, thing = nil)
        a = lAtts({ "class" => "", "link" => 0, "name" => "", "title" => 0, "url" => 0, "wraptag" => "" }, atts)

        sec = if Php.truthy?(a["name"])
          a["name"]
        elsif @thissection && Php.truthy?(@thissection["name"])
          @thissection["name"]
        elsif @thisarticle && Php.truthy?(@thisarticle["section"])
          @thisarticle["section"]
        else
          @pretext["s"]
        end

        if Php.truthy?(sec)
          label = txpspecialchars(Php.truthy?(a["title"]) ? fetch_section_title(sec) : sec)
          url = pagelinkurl({ "s" => sec })
          klass = Php.truthy?(a["class"]) && Php.empty?(a["wraptag"]) ? %( class="#{txpspecialchars(a['class'])}") : ""

          out = if Php.truthy?(thing)
            href(parse(thing), url, klass + (Php.truthy?(a["title"]) ? %( title="#{label}") : ""))
          elsif Php.truthy?(a["link"])
            href(label, url, klass)
          elsif Php.truthy?(a["url"])
            url
          else
            label
          end
          do_tag(out, a["wraptag"], a["class"])
        elsif Php.truthy?(thing)
          parse(thing, false)
        end
      end

      def tag_section_list(atts, thing = nil)
        a = lAtts({
          "active_class" => "", "break" => "br", "class" => "section_list", "default_title" => get_pref("sitename"),
          "exclude" => "", "filter" => false, "form" => "", "html_id" => "", "include_default" => "",
          "sections" => "", "sort" => "", "wraptag" => "", "offset" => "", "limit" => ""
        }, atts)
        sql_limit = ""
        sql_sort = sanitize_for_sort(a["sort"])
        sql = {}
        sections = a["sections"]
        include_default = Php.truthy?(a["include_default"])

        if a["limit"] != "" || Php.truthy?(a["offset"])
          sql_limit = " LIMIT #{Php.intval(a['offset'])}, #{a['limit'] == '' ? (1 << 62) : Php.intval(a['limit'])}"
        end

        if sections == true
          sql["page"] = ""
        elsif Php.truthy?(sections)
          sections = "#{sections}, default" if include_default
          list = DB.quote_list(Php.do_list_unique(sections))
          sql[:in] = " AND name IN (#{list})"
          sql_sort = "FIELD(name, #{list})" if sql_sort == ""
        else
          sql["page"] = filter_front_page("", [ "page" ])
        end

        Php.do_list(a["filter"]).each { |f| sql[f] = filter_front_page("", [ f ]) } if Php.truthy?(a["filter"])

        exclude = a["exclude"]
        if exclude == true
          sql["searchable"] = " AND searchable"
        elsif Php.truthy?(exclude)
          sql[:not_in] = " AND name NOT IN (#{DB.quote_list(Php.do_list_unique(exclude))})"
        end

        sql[:default] = " AND name != 'default'" unless include_default
        sql_sort = "name ASC" if sql_sort == ""
        sql_sort = "name != 'default', #{sql_sort}" if include_default

        rows = DB.rows("SELECT name, title, description FROM txp_section WHERE 1#{sql.values.join} ORDER BY #{sql_sort}#{sql_limit}")
        return "" if rows.empty?

        last = rows.length
        old = @thissection
        s = @pretext["s"]
        out = rows.each_with_index.map do |r, i|
          title = r["name"] == "default" ? a["default_title"] : r["title"]

          if a["form"] == "" && thing.nil?
            klass = Php.truthy?(a["active_class"]) && Php.str(s).casecmp?(r["name"]) ? %( class="#{txpspecialchars(a['active_class'])}") : ""
            tag(txpspecialchars(title), "a", "#{klass} href=\"#{pagelinkurl({ 's' => r['name'] })}\"")
          else
            @thissection = {
              "name" => r["name"], "title" => title, "description" => r["description"],
              "is_first" => i.zero?, "is_last" => i == last - 1
            }
            thing.nil? && a["form"] != "" ? parse_form(a["form"]) : parse(thing)
          end
        end
        @thissection = old

        out.any? ? do_wrap(out, a["wraptag"], { "break" => a["break"], "class" => a["class"], "html_id" => a["html_id"] }) : ""
      end

      def tag_if_section(atts, thing = nil)
        a = lAtts({ "filter" => false, "name" => false, "section" => false }, atts)
        s = @pretext["s"]
        section = a["section"]

        section = if section == true
          Php.truthy?(@thissection) ? @thissection["name"] : s
        elsif section == false
          s
        else
          section
        end
        section = "" if section == "default"
        name = a["name"]
        name = Php.do_list(name) unless name == true || name == false
        filter = a["filter"]

        x = if Php.truthy?(section)
          if name == true
            Php.truthy?(@txp_sections.dig(section, "page"))
          else
            name == false || name.include?(section)
          end
        else
          Php.truthy?(filter) || (name.is_a?(Array) && (name.include?("") || name.include?("default")))
        end

        if x && Php.truthy?(filter)
          Php.do_list(filter).each do |f|
            empty = if Php.truthy?(section)
              Php.empty?(@txp_sections.dig(section, f))
            else
              @txp_sections.values.none? { |r| Php.truthy?(r[f]) }
            end
            if empty
              x = false
              break
            end
          end
        end

        thing.nil? ? x : parse(thing, x)
      end

      def tag_if_article_section(atts, thing = nil)
        a = lAtts({ "filter" => false, "name" => "" }, atts)
        section = @thisarticle ? Php.str(@thisarticle["section"]) : ""
        x = section != "" && (a["name"] == true ? Php.truthy?(@txp_sections.dig(section, "page")) : Php.in_list(section, a["name"]))

        if x && Php.truthy?(a["filter"])
          Php.do_list(a["filter"]).each do |f|
            if Php.empty?(@txp_sections.dig(section, f))
              x = false
              break
            end
          end
        end

        thing.nil? ? x : parse(thing, x)
      end
    end
  end
end
