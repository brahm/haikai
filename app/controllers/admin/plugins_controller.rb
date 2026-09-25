module Admin
  # The Plugins panel (event=plugin). Plugins are Ruby code evaluated in the
  # Txp::Plugins DSL (tags, callbacks, admin tabs).
  class PluginsController < BaseController
    self.event_name = "plugin"
    self.default_step = :index

    step "plugin_list", :index
    step "list", :index
    step "plugin_install", :install, post: true
    step "plugin_edit", :edit
    step "plugin_save", :save, post: true
    step "plugin_help", :help
    step "switch_status", :switch_status, post: true
    step "plugin_multi_edit", :multi_edit, post: true

    private

    def index
      @page_title = gTxt("tab_plugins")
      @plugins = Plugin.order(:load_order, :name).to_a
      Txp::Plugins.load!
      @errors = Txp::Plugins.errors
      render "admin/plugins/index"
    end

    def install
      content = if (file = upload_param(:plugin_file))
        File.read(file.path, encoding: "UTF-8")
      else
        params[:plugin].to_s
      end
      data = Txp::Plugins.parse_package(content)
      if data.blank? || data["name"].blank?
        return redirect_with_message(admin_url(event: "plugin"), gTxt("plugin_invalid"), :error)
      end

      plugin = Plugin.find_or_initialize_by(name: data["name"].to_s)
      php = data["php"]
      plugin.assign_attributes(
        version: data["version"].to_s.presence || "1.0", author: data["author"].to_s, author_uri: data["author_uri"].to_s,
        description: data["description"].to_s, help: data["help"].to_s, type: data["type"].to_i,
        load_order: data["load_order"].to_i.clamp(1, 9), code: php ? "# PHP plugin (not executable)\n=begin\n#{data['code']}\n=end\n" : data["code"].to_s
      )
      plugin.status = 0 if php || plugin.new_record?
      plugin.save!
      Txp::Plugins.reset!
      msg = gTxt("plugin_installed", "{name}" => plugin.name)
      msg += " #{gTxt('plugin_php_warning')}" if php
      redirect_with_message(admin_url(event: "plugin"), msg, php ? :warning : :success)
    rescue ActiveRecord::RecordInvalid => e
      redirect_with_message(admin_url(event: "plugin"), e.message, :error)
    end

    def edit
      @plugin = Plugin.find_by(name: params[:name])
      return redirect_with_message(admin_url(event: "plugin"), gTxt("not_found"), :error) unless @plugin

      @page_title = gTxt("edit_plugin", "{name}" => @plugin.name)
      render "admin/plugins/edit"
    end

    def save
      plugin = Plugin.find_by(name: params[:name])
      return redirect_with_message(admin_url(event: "plugin"), gTxt("not_found"), :error) unless plugin

      plugin.update!(code: params[:code].to_s.gsub("\r\n", "\n"), load_order: params[:load_order].to_i.clamp(1, 9),
        version: params[:version].presence || plugin.version, description: params[:description].to_s, help: params[:help].to_s)
      Txp::Plugins.reset!
      Txp::Plugins.load!
      err = Txp::Plugins.errors[plugin.name]
      redirect_with_message(admin_url(event: "plugin", step: "plugin_edit", name: plugin.name),
        err ? "#{gTxt('plugin_errors')}: #{err}" : gTxt("plugin_updated", "{name}" => plugin.name), err ? :error : :success)
    end

    def help
      @plugin = Plugin.find_by(name: params[:name])
      return redirect_with_message(admin_url(event: "plugin"), gTxt("not_found"), :error) unless @plugin

      @page_title = "#{gTxt('plugin_help')}: #{@plugin.name}"
      render "admin/plugins/help"
    end

    def switch_status
      plugin = Plugin.find_by(name: params[:name])
      plugin&.update!(status: plugin.active? ? 0 : 1)
      Txp::Plugins.reset!
      redirect_to admin_url(event: "plugin")
    end

    def multi_edit
      plugins = Plugin.where(name: selected_ids).to_a
      names = plugins.map(&:name)
      case params[:edit_method]
      when "delete"
        plugins.each(&:destroy)
        LangString.where(owner: names).delete_all
        Txp::Plugins.reset!
        redirect_with_message(admin_url(event: "plugin"), gTxt("plugins_deleted", "{list}" => names.join(", ")))
      when "activate", "deactivate"
        plugins.each { |p| p.update!(status: params[:edit_method] == "activate" ? 1 : 0) }
        Txp::Plugins.reset!
        redirect_with_message(admin_url(event: "plugin"), gTxt("items_updated", "{list}" => names.join(", ")))
      when "changeorder"
        plugins.each { |p| p.update!(load_order: params[:order].to_i.clamp(1, 9)) }
        Txp::Plugins.reset!
        redirect_with_message(admin_url(event: "plugin"), gTxt("items_updated", "{list}" => names.join(", ")))
      else
        redirect_to admin_url(event: "plugin")
      end
    end
  end
end
