module Admin
  # The Diagnostics panel (event=diag).
  class DiagnosticsController < BaseController
    self.event_name = "diag"
    self.default_step = :index

    step "prefs_list", :index

    private

    def index
      @page_title = gTxt("tab_diagnostics")
      @checks = checks
      img_dir = Txp::Images.dir(@prefs)
      @info = {
        "Textpattern (Rails) version" => Txp::VERSION,
        "Ruby" => "#{RUBY_VERSION} (#{RUBY_PLATFORM})",
        "Rails" => Rails.version,
        "SQLite" => ActiveRecord::Base.connection.select_value("SELECT sqlite_version()"),
        gTxt("database") => ActiveRecord::Base.connection_db_config.database,
        "Environment" => Rails.env,
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
      render "admin/diagnostics/index"
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
