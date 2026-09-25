module Admin
  # The Sections panel (event=section).
  class SectionsController < BaseController
    self.event_name = "section"
    self.default_step = :index

    step "section_list", :index
    step "list", :index
    step "section_edit", :edit
    step "section_save", :save, post: true
    step "section_set_default", :set_default, post: true
    step "section_multi_edit", :multi_edit, post: true

    SORTS = { "name" => "name", "title" => "title", "skin" => "skin", "page" => "page", "css" => "css",
              "permlink_mode" => "permlink_mode", "on_frontpage" => "on_frontpage", "in_rss" => "in_rss",
              "searchable" => "searchable" }.freeze
    PERMLINK_MODES = %w[section_id_title year_month_day_title section_title title_only id_title section_category_title breadcrumb_title messy].freeze

    private

    def index
      @page_title = gTxt("tab_sections")
      @state = list_state("section", SORTS.keys, "name", "asc")
      scope = Section.order(Arel.sql("name != 'default', #{SORTS[@state[:sort]]} #{@state[:dir]}, name"))
      crit = params[:crit].to_s.strip
      scope = scope.where("name LIKE :q OR title LIKE :q", q: "%#{Section.sanitize_sql_like(crit)}%") if crit.present?
      @sections = paginate(scope, @state).to_a
      @counts = Article.group(:Section).count
      render "admin/sections/index"
    end

    def edit
      @section = params[:name].present? ? Section.find_by(name: params[:name]) : Section.new(
        skin: Section.where(name: "default").pick(:skin), page: "default", css: "default", on_frontpage: 1, in_rss: 1, searchable: 1
      )
      return redirect_with_message(admin_url(event: "section"), gTxt("not_found"), :error) unless @section

      prepare_form
      render "admin/sections/edit"
    end

    def prepare_form
      @page_title = @section.persisted? ? gTxt("edit_section") : gTxt("create_section")
      @skins = Skin.order(:title).pluck(:title, :name)
      @pages = Page.order(:name).pluck(:skin, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
      @styles = Style.order(:name).pluck(:skin, :name).group_by(&:first).transform_values { |v| v.map(&:last) }
    end

    def save
      return require_privs!("section.edit") unless has_privs?("section.edit")

      old_name = params[:old_name].to_s
      @section = old_name.present? ? Section.find_by(name: old_name) : Section.new
      return redirect_with_message(admin_url(event: "section"), gTxt("not_found"), :error) unless @section

      name = old_name == "default" ? "default" : Txp::Text.strip_space(params[:name].presence || params[:title], @prefs, force: true).to_s
      if name.empty?
        announce(gTxt("invalid_name"), :error)
        prepare_form
        return render("admin/sections/edit", status: :unprocessable_entity)
      end
      if name != old_name && Section.exists?(name: name)
        announce(gTxt("name_already_exists", "{name}" => name), :error)
        prepare_form
        return render("admin/sections/edit", status: :unprocessable_entity)
      end

      attrs = {
        title: params[:title].presence || name, description: params[:description].to_s, skin: params[:skin].to_s,
        page: params[:page].to_s, css: params[:css].to_s, permlink_mode: PERMLINK_MODES.include?(params[:permlink_mode]) ? params[:permlink_mode] : "",
        on_frontpage: params[:on_frontpage].to_i, in_rss: params[:in_rss].to_i, searchable: params[:searchable].to_i,
        dev_skin: params[:dev_skin].to_s, dev_page: params[:dev_page].to_s, dev_css: params[:dev_css].to_s
      }

      Section.transaction do
        if @section.persisted? && name != old_name
          Section.where(name: old_name).update_all(name: name)
          Article.where(Section: old_name).update_all(Section: name)
          Pref.set("default_section", name, event: "section", type: Txp::PREF_HIDDEN) if @prefs["default_section"] == old_name
          @section = Section.find_by(name: name)
        else
          @section.name = name
        end
        @section.update!(attrs)
      end

      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "section"), gTxt(old_name.present? ? "section_saved" : "section_created", "{name}" => name))
    end

    def set_default
      name = params[:default_section].to_s
      Pref.set("default_section", name, event: "section", type: Txp::PREF_HIDDEN) if Section.where.not(name: "default").exists?(name: name)
      redirect_with_message(admin_url(event: "section"), gTxt("default_section_updated"))
    end

    def multi_edit
      return require_privs!("section.edit") unless has_privs?("section.edit")

      sections = Section.where(name: selected_ids).to_a
      names = sections.map(&:name)
      case params[:edit_method]
      when "delete"
        in_use = sections.select { |s| s.name == "default" || Article.exists?(Section: s.name) }
        (sections - in_use).each(&:destroy)
        msg = gTxt("sections_deleted", "{list}" => (names - in_use.map(&:name)).join(", "))
        msg += " #{gTxt('section_has_articles', '{list}' => in_use.map(&:name).join(', '))}" if in_use.any?
        return redirect_with_message(admin_url(event: "section"), msg, in_use.any? ? :warning : :success)
      when "changepage" then sections.each { |s| s.update(page: params[:page].to_s) }
      when "changecss" then sections.each { |s| s.update(css: params[:css].to_s) }
      when "changeskin"
        skin = params[:skin].to_s
        sections.each { |s| s.update(skin: skin) } if Skin.exists?(name: skin)
      when "change_frontpage" then sections.each { |s| s.update(on_frontpage: params[:on_frontpage].to_i) }
      when "change_syndicate" then sections.each { |s| s.update(in_rss: params[:in_rss].to_i) }
      when "change_searchable" then sections.each { |s| s.update(searchable: params[:searchable].to_i) }
      end
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "section"), gTxt("items_updated", "{list}" => names.join(", ")))
    end
  end
end
