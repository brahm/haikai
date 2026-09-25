require "etc"

module Admin
  # The Diagnostics panel (event=diag): Textpattern's low and high detail
  # levels (step=low|high), optionally without private information.
  class DiagnosticsController < BaseController
    self.event_name = "diag"
    self.default_step = :index

    step "prefs_list", :index

    private

    def index
      @page_title = gTxt("tab_diagnostics")
      @detail = step == "high" ? "high" : "low"
      @clear_private = params[:clear_private].present?
      @checks = checks
      img_dir = Txp::Images.dir(@prefs)
      os = Etc.uname.values_at(*(@detail == "high" ? %i[sysname release version machine] : %i[sysname release]))
      info = {
        "Textpattern (Rails) version" => Txp::VERSION,
        "Ruby" => "#{RUBY_VERSION} (#{RUBY_PLATFORM})",
        "Rails" => Rails.version,
        "SQLite" => ActiveRecord::Base.connection.select_value("SELECT sqlite_version()"),
        gTxt("database") => ActiveRecord::Base.connection_db_config.database,
        "Environment" => Rails.env,
        "Server OS" => os.join(" "),
        "Site URL (pref)" => @prefs["siteurl"].presence || "-",
        "Site URL (request)" => site_url,
        "Admin URL" => "#{site_url}textpattern/",
        "Document root" => Rails.public_path.to_s,
        "Image directory" => img_dir.to_s,
        "File directory" => TxpFile.base_path.to_s,
        "Themes directory" => Txp::ThemeIO.skin_dir(@prefs).to_s,
        "ImageMagick" => Txp::Images.magick || "-",
        "Permanent link mode" => @prefs["permlink_mode"],
        "Production status" => @prefs["production_status"],
        "Time zone" => @prefs["timezone_key"],
        "Site language" => @prefs["language"],
        "Admin theme" => admin_theme.name,
        "Public themes" => Skin.order(:name).pluck(:name).join(", "),
        gTxt("active_plugins") => Plugin.where(status: 1).order(:name).pluck(:name, :version).map { |n, v| "#{n}-#{v}" }.join(", ").presence || "-",
        "Registered tags" => Txp::Registry.default.tags.size,
        "Articles / images / files / links / comments" => [ Article.count, Image.count, TxpFile.count, Link.count, Comment.count ].join(" / ")
      }
      info.merge!(high_detail) if @detail == "high"
      # Addresses and paths, which "Hide private information" leaves out.
      private_keys = [ gTxt("database"), "Site URL (pref)", "Site URL (request)", "Admin URL", "Document root",
                       "Image directory", "File directory", "Themes directory" ]
      @info = @clear_private ? info.except(*private_keys) : info
      render "admin/diagnostics/index"
    end

    # What Textpattern's high level adds (database check, tables, custom
    # fields, extensions...), for this stack.
    def high_detail
      db = ActiveRecord::Base.connection
      tables = db.tables.sort
      path = Rails.root.join(ActiveRecord::Base.connection_db_config.database.to_s)
      custom = @prefs.select { |name, _| name.match?(/\Acustom_\d+_set\z/) }.values.reject(&:blank?)
      {
        "Database check" => db.select_value("PRAGMA quick_check"),
        "Database journal mode" => db.select_value("PRAGMA journal_mode"),
        "Database size" => File.file?(path) ? ActiveSupport::NumberHelper.number_to_human_size(File.size(path)) : "-",
        "Database tables (#{tables.size})" => tables.map { |t| "#{t} (#{db.select_value("SELECT COUNT(*) FROM #{db.quote_table_name(t)}")})" }.join(", "),
        "Custom fields (#{custom.size})" => custom.join(", ").presence || "-",
        "Mail delivery" => Txp::MailDelivery.smtp_settings(@prefs) ? "SMTP" : "sendmail",
        "SMTP_* variables set" => Txp::MailDelivery::ENV_KEYS.map(&:upcase).select { |k| ENV[k].present? }.join(", ").presence || "-",
        "Installed plugins" => Plugin.order(:name).pluck(:name, :version, :status)
          .map { |n, v, s| "#{n}-#{v}#{' (disabled)' unless s.to_i == 1}" }.join(", ").presence || "-",
        "Gems" => Gem.loaded_specs.values.sort_by(&:name).map { |s| "#{s.name}-#{s.version}" }.join(", ")
      }
    end

    def checks
      list = []
      dirs = { gTxt("img_dir") => Txp::Images.dir(@prefs), gTxt("file_base_path") => TxpFile.base_path,
               gTxt("tempdir") => Rails.root.join("tmp"), "log" => Rails.root.join("log") }
      dirs.each do |label, dir|
        if !File.directory?(dir)
          list << [ :warning, gTxt("dir_missing", "{dir}" => dir.to_s) ]
        elsif !File.writable?(dir)
          list << [ :error, gTxt("dir_not_writable", "{dirtype}" => label, "{path}" => dir.to_s) ]
        end
      end
      if @prefs["siteurl"].present? && @prefs["siteurl"] != request.host_with_port
        list << [ :warning, gTxt("site_url_mismatch", "{url}" => @prefs["siteurl"]) ]
      end
      list << [ :warning, gTxt("imagemagick_missing") ] unless Txp::Images.magick
      list << [ :error, gTxt("missing_default_section") ] unless Section.exists?(name: "default")
      missing = Section.all.reject { |s| Page.exists?(name: s.page, skin: s.skin) }.map(&:name)
      list << [ :error, gTxt("missing_pages", "{list}" => missing.join(", ")) ] if missing.any?
      Txp::Plugins.errors.each { |name, err| list << [ :error, "#{name}: #{err}" ] }
      list
    end
  end
end
