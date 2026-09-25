module Admin
  # Base class for admin panels. Each panel ("event") declares its steps; the
  # requested ?step= is dispatched like Textpattern's bouncer().
  class BaseController < ApplicationController
    layout "admin"

    before_action :load_prefs
    before_action :require_login
    before_action :load_admin_plugins

    helper_method :gTxt, :prefs, :has_privs?, :admin_url, :event, :step, :lang_ui, :admin_theme, :txp_areas,
      :message, :site_url, :format_admin_date, :can_edit_article?

    class_attribute :event_name, default: nil
    class_attribute :event_priv, default: nil
    class_attribute :steps, default: {}
    class_attribute :default_step, default: nil

    # step "edit" => :edit_action, "save" => :save (POST only when post: true)
    def self.step(name, method = nil, post: false)
      self.steps = steps.merge(name.to_s => { method: (method || name).to_sym, post: post })
    end

    def handle
      require_privs!(event_priv || event_name)
      return if performed?

      name = params[:step].to_s
      spec = steps[name]
      spec = nil if spec && spec[:post] && !request.post?
      method = spec ? spec[:method] : default_step
      send(method)
    end

    private

    def event
      event_name || params[:event].to_s
    end

    def step
      params[:step].to_s
    end

    def load_prefs
      @prefs = Pref.site_prefs(current_user&.name)
    end

    def prefs
      @prefs
    end

    def lang_ui
      @lang_ui ||= Txp::Textpack.normalize(@prefs["language_ui"].presence || @prefs["language"].presence || "en")
    end

    # Like Textpattern, localised strings are trusted HTML (e.g. "Pages
    # updated: <strong>{list}</strong>.") while replacement values are escaped.
    def gTxt(key, atts = {}, escape = "html")
      text = Txp::Textpack.txt(lang_ui, key, atts, escape)
      escape == "html" ? text.html_safe : text
    end

    def require_login
      return if current_user

      if request.xhr?
        head :unauthorized
      else
        redirect_to admin_root_path(return_to: request.fullpath.start_with?("/textpattern") ? request.fullpath : nil)
      end
    end

    def load_admin_plugins
      Txp::Plugins.load! if Txp::Php.truthy?(@prefs["use_plugins"]) && Txp::Php.truthy?(@prefs["admin_side_plugins"])
    end

    def has_privs?(resource, user = current_user)
      return false unless user

      Txp::Privs.has?(resource, user.privs)
    end

    def require_privs!(resource)
      return if resource.nil? || has_privs?(resource)

      @page_title = gTxt("restricted_area")
      render "admin/shared/restricted", status: :forbidden
    end

    def admin_url(params = {})
      query = params.compact.to_query
      "/textpattern/index.php#{query.empty? ? '' : "?#{query}"}"
    end

    def site_url
      "#{request.protocol}#{request.host_with_port}/"
    end

    # Absolute admin URL for links sent by email. The host comes from the site
    # URL preference, not from the Host header, which anyone can forge to have
    # a password reset link point at their server. Until the preference is set,
    # only a logged-in user's own request stands in for it. Nil without a host.
    def emailed_admin_url(params)
      host = @prefs["siteurl"].to_s.sub(%r{\Ahttps?://}, "").chomp("/")
      host = "#{request.host_with_port}#{request.script_name}" if host.empty? && current_user
      "#{request.protocol}#{host}#{admin_url(params)}" if host.present?
    end

    # Records the site URL when there is none yet: the installer's field (like
    # Textpattern's setup), else the address of the request, for sites
    # installed from the command line without SITE_URL. Returns what it set.
    def remember_site_url(url = nil)
      return if @prefs["siteurl"].present?

      url = url.to_s.strip.sub(%r{\Ahttps?://}, "").chomp("/").presence || "#{request.host_with_port}#{request.script_name}"
      Pref.set("siteurl", url, event: "site", position: 40)
      @prefs["siteurl"] = url
    end

    def admin_theme
      @admin_theme ||= Txp::AdminTheme.find(@prefs["theme_name"])
    end

    # Menu areas (areas()): tab => [[label, event], ...]
    def txp_areas
      admin_label = has_privs?("admin.list") ? gTxt("tab_site_admin") : gTxt("tab_site_account")
      areas = {
        "content" => [ [ gTxt("tab_write"), "article" ], [ gTxt("tab_list"), "list" ], [ gTxt("tab_image"), "image" ],
                      [ gTxt("tab_file"), "file" ], [ gTxt("tab_link"), "link" ], [ gTxt("tab_organise"), "category" ] ],
        "presentation" => [ [ gTxt("tab_skin"), "skin" ], [ gTxt("tab_sections"), "section" ], [ gTxt("tab_pages"), "page" ],
                           [ gTxt("tab_forms"), "form" ], [ gTxt("tab_style"), "css" ] ],
        "admin" => [ [ gTxt("tab_diagnostics"), "diag" ], [ gTxt("tab_preferences"), "prefs" ], [ gTxt("tab_languages"), "lang" ],
                    [ admin_label, "admin" ], [ gTxt("tab_plugins"), "plugin" ] ],
        "extensions" => []
      }
      areas["content"] << [ gTxt("tab_comments"), "discuss" ] if Txp::Php.truthy?(@prefs["use_comments"])
      areas["admin"] << [ gTxt("tab_logs"), "log" ] if @prefs["logging"].to_s != "none" && Txp::Php.truthy?(@prefs["expire_logs_after"])
      Txp::Plugins.admin_tabs.each { |area, list| (areas[area] ||= []).concat(list.map { |label, ev| [ label, ev ] }) }
      areas.select { |area, _| has_privs?("tab.#{area}") || area == "extensions" }
           .transform_values { |items| items.select { |_, ev| has_privs?(ev) || Txp::Plugins.admin_panels.key?(ev) } }
    end

    # Messages shown in the message pane: [text, :success | :error | :warning | :info]
    def message
      @message || flash[:txp_message]
    end

    def announce(text, type = :success)
      @message = [ text, type ]
    end

    def redirect_with_message(url, text, type = :success)
      flash[:txp_message] = [ text, type ]
      redirect_to url
    end

    def format_admin_date(value, format = "%Y-%m-%d %H:%M")
      return "" if value.nil?

      Txp.zone(@prefs).at(value.to_i).strftime(format)
    end

    def zone
      Txp.zone(@prefs)
    end

    def can_edit_article?(article, user = current_user)
      return false unless user

      own = article.AuthorID == user.name
      published = article.live?
      if own
        published ? has_privs?("article.edit.own.published") : has_privs?("article.edit.own")
      else
        published ? has_privs?("article.edit.published") : has_privs?("article.edit")
      end
    end

    # Persists a per-user preference (e.g. list sort order, page size).
    def set_user_pref(name, value, event_name = event)
      Pref.set(name, value, event: event_name, type: Txp::PREF_HIDDEN, user: current_user.name)
      @prefs[name] = value.to_s
    end

    # Sort/paging state for list panels, remembered per user like Textpattern.
    def list_state(prefix, columns, default_sort, default_dir = "desc")
      sort = params[:sort].presence || @prefs["#{prefix}_sort_column"].presence || default_sort
      sort = default_sort unless columns.include?(sort)
      dir = params[:dir].presence || @prefs["#{prefix}_sort_dir"].presence || default_dir
      dir = %w[asc desc].include?(dir) ? dir : default_dir
      set_user_pref("#{prefix}_sort_column", sort) if params[:sort].present?
      set_user_pref("#{prefix}_sort_dir", dir) if params[:dir].present?

      set_user_pref("#{prefix}_list_pageby", closest_pageby(params[:qty])) if params[:qty].present?
      limit = closest_pageby(@prefs["#{prefix}_list_pageby"])
      page = [ params[:page].to_i, 1 ].max
      { sort: sort, dir: dir, limit: limit, page: page, offset: (page - 1) * limit }
    end

    # ORDER BY terms for list panels: SQL expressions from the panel's SORTS
    # whitelist, in the list's direction.
    def sort_terms(state, *columns)
      columns.map { |sql| state[:dir] == "asc" ? Arel.sql(sql).asc : Arel.sql(sql).desc }
    end

    # \Textpattern\Admin\Paginator: list sizes and closest().
    PAGEBY_SIZES = [ 12, 24, 48, 96 ].freeze

    def closest_pageby(value)
      value = value.to_i
      return PAGEBY_SIZES.first unless value.positive?

      PAGEBY_SIZES.min_by { |size| [ (size - value).abs, size ] }
    end

    def paginate(scope, state)
      total = scope.count
      pages = [ (total.to_f / state[:limit]).ceil, 1 ].max
      page = [ state[:page], pages ].min
      state.merge!(page: page, offset: (page - 1) * state[:limit], total: total, pages: pages)
      scope.limit(state[:limit]).offset(state[:offset])
    end

    def selected_ids
      Array(params[:selected]).map(&:to_s).reject(&:empty?)
    end

    def upload_param(name)
      f = params[name]
      f.respond_to?(:original_filename) ? f : nil
    end
  end
end
