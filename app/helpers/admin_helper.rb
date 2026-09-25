# View helpers reproducing Textpattern's admin UI building blocks
# (inputLabel, fInput, selectInput, yesnoRadio, column_head, nav_form...).
module AdminHelper
  # <div class="txp-form-field ..."><div class="txp-form-field-label">...</div><div class="txp-form-field-value">...</div></div>
  def input_label(id, input, label_key, help: nil, klass: nil, label_text: nil)
    label = label_text || (label_key ? gTxt(label_key) : "")
    help_html = help ? pophelp(help) : "".html_safe
    content_tag(:div, class: [ "txp-form-field", klass || "#{id.to_s.tr('_', '-')}" ].join(" ")) do
      content_tag(:div, class: "txp-form-field-label") do
        (id ? label_tag(id, label) : content_tag(:span, label)) + help_html
      end +
        content_tag(:div, input, class: "txp-form-field-value")
    end
  end

  # popHelp(): link to an inline help topic (only when the topic exists and
  # the module_pophelp preference is on).
  def pophelp(key, klass: "pophelp")
    return "".html_safe unless key.present? && Txp::Php.truthy?(prefs["module_pophelp"]) && Txp::Pophelp.exists?(key, lang_ui)

    link = link_to(content_tag(:span, gTxt("help"), class: "ui-icon ui-icon-help"), admin_url(event: "help", step: "pophelp", item: key),
      rel: "help", title: gTxt("help"), role: "button", class: klass)
    safe_join([ " ", link ])
  end

  def txp_text_field(name, value, id: nil, size: nil, klass: nil, **opts)
    text_field_tag(name, value, { id: id || name.to_s.gsub(/[\[\]]+/, "_").chomp("_"), size: size, class: klass }.merge(opts))
  end

  def txp_select(name, choices, selected, id: nil, include_blank: false, klass: nil, **opts)
    options = include_blank ? [ [ "", "" ] ] + choices.to_a : choices.to_a
    select_tag(name, options_for_select(options, selected.to_s), { id: id || name, class: klass }.merge(opts))
  end

  def yes_no_radio(name, value, id: nil)
    id ||= name
    content_tag(:div, class: "txp-radio-set") do
      radio_button_tag(name, "1", value.to_s == "1", id: "#{id}-1") + label_tag("#{id}-1", gTxt("yes")) + " " +
        radio_button_tag(name, "0", value.to_s != "1", id: "#{id}-0") + label_tag("#{id}-0", gTxt("no"))
    end
  end

  def on_off_radio(name, value, id: nil)
    id ||= name
    content_tag(:div, class: "txp-radio-set") do
      radio_button_tag(name, "1", value.to_s == "1", id: "#{id}-1") + label_tag("#{id}-1", gTxt("on")) + " " +
        radio_button_tag(name, "0", value.to_s != "1", id: "#{id}-0") + label_tag("#{id}-0", gTxt("off"))
    end
  end

  def txp_submit(label_key, klass: "publish", name: nil, **opts)
    submit_tag(gTxt(label_key), { class: klass, name: name, data: { disable_with: false } }.merge(opts))
  end

  def event_hidden(event_name, step_name = nil)
    hidden_field_tag(:event, event_name, id: nil) + (step_name ? hidden_field_tag(:step, step_name, id: nil) : "".html_safe)
  end

  # Sortable list column heading (column_head()).
  def column_head(label_key, sort_key, state, event_name, step_name: "list", klass: nil, extra: {})
    current = state[:sort] == sort_key
    dir = current && state[:dir] == "asc" ? "desc" : "asc"
    dir = "desc" if !current && %w[posted lastmod date time created modified id].include?(sort_key)
    classes = [ "txp-list-col-#{klass || sort_key}", (current ? state[:dir] : nil) ].compact.join(" ")
    link = link_to(gTxt(label_key), admin_url({ event: event_name, step: step_name, sort: sort_key, dir: dir, crit: params[:crit], search_method: params[:search_method] }.merge(extra)))
    content_tag(:th, link, scope: "col", class: classes)
  end

  def plain_head(label_key, klass)
    content_tag(:th, gTxt(label_key), scope: "col", class: "txp-list-col-#{klass}")
  end

  def select_all_head
    content_tag(:th, check_box_tag("select_all", 0, false, class: "checkbox", title: gTxt("toggle_all_selected"), "aria-label": gTxt("toggle_all_selected"), id: nil), class: "txp-list-col-multi-edit", scope: "col", title: gTxt("toggle_all_selected"))
  end

  def select_cell(value)
    content_tag(:td, check_box_tag("selected[]", value, false, class: "checkbox", id: nil), class: "txp-list-col-multi-edit")
  end

  # Pagination controls (nav_form()).
  def txp_pager(state, event_name, step_name: "list", extra: {})
    return "".html_safe if state[:pages].to_i <= 1

    base = { event: event_name, step: step_name, sort: state[:sort], dir: state[:dir], crit: params[:crit], search_method: params[:search_method] }.merge(extra)
    page = state[:page]
    pages = state[:pages]
    items = []
    items << (page > 1 ? link_to(gTxt("prev"), admin_url(base.merge(page: page - 1)), class: "prev", rel: "prev", title: gTxt("prev")) : content_tag(:span, gTxt("prev"), class: "disabled"))
    window = ((page - 2)..(page + 2)).select { |p| p.between?(1, pages) }
    items << link_to("1", admin_url(base.merge(page: 1))) << content_tag(:span, "…") if window.first > 1
    window.each do |p|
      items << (p == page ? content_tag(:span, p, class: "current", "aria-current": "page") : link_to(p, admin_url(base.merge(page: p))))
    end
    items << content_tag(:span, "…") << link_to(pages, admin_url(base.merge(page: pages))) if window.last < pages
    items << (page < pages ? link_to(gTxt("next"), admin_url(base.merge(page: page + 1)), class: "next", rel: "next", title: gTxt("next")) : content_tag(:span, gTxt("next"), class: "disabled"))
    content_tag(:nav, safe_join(items, " "), class: "prev-next", "aria-label": gTxt("page_nav"))
  end

  TIMEZONE_CONTINENTS = %w[Africa America Antarctica Arctic Asia Atlantic Australia Europe Indian Pacific].freeze

  # timezoneSelectInput(): time zones grouped by continent, like
  # \Textpattern\Date\Timezone::getTimeZones() (DateTimeZone::listIdentifiers()).
  def timezone_select_input(name, value, id)
    zones = (TZInfo::Timezone.all_data_zone_identifiers | [ "UTC" ]).select do |tz|
      parts = tz.split("/")
      parts.size == 1 ? tz == "UTC" : TIMEZONE_CONTINENTS.include?(parts[0])
    end.sort

    groups = zones.group_by { |tz| tz.include?("/") ? tz.split("/").first : "" }
    options = groups.map do |continent, list|
      items = list.map do |tz|
        _continent, city, subcity = tz.split("/", 3)
        label = [ city, subcity ].compact.map { |part| gTxt(part.tr("_", " ")) }.join("/").presence || tz
        content_tag(:option, "#{label}\t", value: tz, selected: tz == value, dir: "auto")
      end
      content_tag(:optgroup, safe_join(items), label: gTxt(continent.presence || "Universal"))
    end
    content_tag(:select, safe_join(options), name: name, id: id)
  end

  # \Textpattern\Admin\Paginator::render()
  def pageby_form(event_name, state, step_name: "list")
    links = Admin::BaseController::PAGEBY_SIZES.map do |qty|
      active = qty == state[:limit].to_i
      link_to(qty, admin_url(event: event_name, step: step_name, qty: qty), class: active ? "navlink-active" : "navlink",
        title: gTxt("view_per_page", "{page}" => qty), "aria-pressed": active.to_s, role: "button")
    end
    content_tag(:div, safe_join(links), class: "nav-tertiary pageby")
  end

  def txp_search_form(event_name, methods, placeholder_key, step_name: "list")
    form_tag(admin_url, method: :get, class: "txp-search", role: "search") do
      event_hidden(event_name, step_name) +
        content_tag(:span, class: "txp-search-options") do
          select_tag(:search_method, options_for_select(methods.map { |k, v| [ gTxt(v), k ] }, params[:search_method]), "aria-label": gTxt("search_method"), class: "txp-search-method")
        end +
        search_field_tag(:crit, params[:crit], placeholder: gTxt(placeholder_key), "aria-label": gTxt("search"), class: "txp-search-input") +
        submit_tag(gTxt("search"), class: "txp-search-button", name: nil) +
        (params[:crit].present? ? link_to(gTxt("search_clear"), admin_url(event: event_name), class: "txp-search-clear") : "".html_safe)
    end
  end

  # Multi-edit ("with selected") control.
  def multi_edit(options, event_name, step_name = "multi_edit", extra_fields: {})
    content_tag(:div, class: "multi-edit") do
      content_tag(:label, gTxt("bulk_edit"), class: "txp-accessibility", for: "bulk_edit") +
        select_tag(:edit_method, options_for_select([ [ gTxt("with_selected_option", "{count}" => "0"), "" ] ] + options.map { |k, v| [ v.is_a?(Hash) ? v[:label] : gTxt(v), k ] }),
          id: "bulk_edit", class: "multi-edit-method", data: { txt: Txp::Textpack.txt(lang_ui, "with_selected_option", {}, "") }) +
        safe_join(options.filter_map { |k, v| v.is_a?(Hash) && v[:html] ? content_tag(:span, v[:html], class: "multi-option", data: { for: k }, hidden: true) : nil }) +
        safe_join(extra_fields.map { |k, v| hidden_field_tag(k, v, id: nil) }) +
        event_hidden(event_name, step_name) +
        submit_tag(gTxt("go"), class: "multi-edit-submit", name: nil)
    end
  end

  def status_label(status)
    gTxt(Txp::STATUSES[status.to_i].to_s)
  end

  def status_choices
    Txp::STATUSES.map { |k, v| [ gTxt(v), k ] }
  end

  def section_choices(include_default: false)
    scope = Section.order(:title)
    scope = scope.where.not(name: "default") unless include_default
    scope.map { |s| [ s.name == "default" ? gTxt("default") : s.title.presence || s.name, s.name ] }
  end

  def category_choices(type)
    Category.tree(type).map { |c, level| [ "#{'  ' * level}#{c.title.presence || c.name}".sub(/\A\s+/) { |m| " " * m.length * 2 }, c.name ] }
  end

  def user_choices
    User.order(:name).map { |u| [ u.display_name, u.name ] }
  end

  def group_choices
    Txp::GROUPS.map { |k, v| [ gTxt(v == "none" ? "privs_none" : v), k ] }
  end

  def txp_date_fields(prefix, time, klass: "")
    t = time ? Txp.zone(prefs).at(time.to_i) : nil
    content_tag(:span, class: "txp-date #{klass}") do
      text_field_tag("#{prefix}_date", t&.strftime("%Y-%m-%d"), type: "date", id: "#{prefix}-date", class: "input-date", "aria-label": gTxt("date")) + " " +
        text_field_tag("#{prefix}_time", t&.strftime("%H:%M:%S"), type: "time", step: 1, id: "#{prefix}-time", class: "input-time", "aria-label": gTxt("time"))
    end
  end

  def alert_block(key_or_text, type = "information")
    content_tag(:p, content_tag(:span, "", class: "ui-icon ui-icon-info") + " " + gTxt(key_or_text), class: "alert-block #{type}")
  end

  def txp_heading(text, klass: "txp-heading")
    content_tag(:h1, text, class: klass)
  end

  def txp_button_link(label_key, url, klass: "txp-button")
    link_to(gTxt(label_key), url, class: klass)
  end

  def human_size(bytes)
    number_to_human_size(bytes.to_i)
  end

  def txp_textarea(name, value, id: nil, rows: 12, cols: 60, klass: "code", **opts)
    text_area_tag(name, value, { id: id || name, rows: rows, cols: cols, class: klass, spellcheck: false }.merge(opts))
  end

  def summary_toggle(id, label_key, &block)
    content_tag(:section, class: "txp-details", id: "#{id}_group", "aria-labelledby": "#{id}_label") do
      content_tag(:h3, class: "txp-summary expanded") do
        link_to(gTxt(label_key), "##{id}", role: "button", data: { txp_token: nil }, "aria-controls": id, "aria-pressed": "true", id: "#{id}_label")
      end +
        content_tag(:div, capture(&block), class: "toggle", id: id, role: "group")
    end
  end
end
