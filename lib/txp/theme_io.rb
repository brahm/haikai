module Txp
  # Imports and exports themes using Textpattern's theme directory layout:
  #
  #   <name>/manifest.json
  #   <name>/pages/<page>.txp
  #   <name>/forms/<type>/<form>.txp
  #   <name>/styles/<style>.css
  #
  # so that Textpattern themes (e.g. from textpattern.com or GitHub) can be
  # used unchanged, and themes built here can be used by Textpattern.
  module ThemeIO
    module_function

    def skin_dir(prefs = Pref.site_prefs)
      Rails.root.join("public", prefs.fetch("skin_dir", "themes").presence || "themes")
    end

    # Reads a theme directory into a Hash (without touching the database).
    def read_dir(dir)
      dir = Pathname.new(dir)
      raise ArgumentError, "theme directory not found: #{dir}" unless dir.directory?

      manifest = {}
      if (m = dir.join("manifest.json")).file?
        manifest = JSON.parse(File.read(m)) rescue {}
      end

      pages = Dir[dir.join("pages", "*.{txp,html}")].sort.to_h { |f| [ File.basename(f).sub(/\.(txp|html)\z/, ""), File.read(f, encoding: "UTF-8") ] }
      styles = Dir[dir.join("styles", "*.css")].sort.to_h { |f| [ File.basename(f, ".css"), File.read(f, encoding: "UTF-8") ] }
      forms = {}
      Dir[dir.join("forms", "*", "*.{txp,html}")].sort.each do |f|
        type = File.basename(File.dirname(f))
        forms[File.basename(f).sub(/\.(txp|html)\z/, "")] = { "type" => type, "Form" => File.read(f, encoding: "UTF-8") }
      end

      { "manifest" => manifest, "pages" => pages, "forms" => forms, "styles" => styles }
    end

    # Imports (or updates) a theme from a directory. Returns the Skin.
    def import(dir, name: nil, overwrite: true)
      data = read_dir(dir)
      name ||= Text.sanitize_for_theme(File.basename(dir.to_s))
      import_data(name, data, overwrite: overwrite)
    end

    def import_data(name, data, overwrite: true)
      manifest = data["manifest"] || {}
      now = Time.now.utc.change(usec: 0)

      ActiveRecord::Base.transaction do
        skin = Skin.find_or_initialize_by(name: name)
        skin.assign_attributes(
          title: manifest["title"].presence || name.titleize,
          version: manifest["version"].to_s.presence || "1.0",
          description: manifest["description"].to_s,
          author: manifest["author"].to_s,
          author_uri: manifest["author_uri"].to_s,
          lastmod: now
        )
        skin.save!

        if overwrite
          Page.where(skin: name).where.not(name: data["pages"].keys).delete_all
          Form.where(skin: name).where.not(name: data["forms"].keys).delete_all
          Style.where(skin: name).where.not(name: data["styles"].keys).delete_all
        end

        data["pages"].each do |pname, html|
          rec = Page.find_or_initialize_by(name: pname, skin: name)
          rec.update!(user_html: html) if overwrite || rec.new_record?
        end

        data["forms"].each do |fname, f|
          rec = Form.find_or_initialize_by(name: fname, skin: name)
          rec.update!(type: f["type"], Form: f["Form"]) if overwrite || rec.new_record?
        end

        data["styles"].each do |sname, css|
          rec = Style.find_or_initialize_by(name: sname, skin: name)
          rec.update!(css: css) if overwrite || rec.new_record?
        end

        skin
      end
    end

    # Writes a theme to a directory (public/themes/<name> by default).
    def export(name, dir = nil)
      skin = Skin.find(name)
      dir = Pathname.new(dir || skin_dir.join(name))
      FileUtils.mkdir_p(dir.join("pages"))
      FileUtils.mkdir_p(dir.join("styles"))

      manifest = {
        "title" => skin.title, "txp-type" => "textpattern-theme", "description" => skin.description.to_s,
        "author" => skin.author.to_s, "author_uri" => skin.author_uri.to_s, "version" => skin.version.to_s
      }
      File.write(dir.join("manifest.json"), JSON.pretty_generate(manifest))

      Dir[dir.join("pages", "*.txp")].each { |f| FileUtils.rm_f(f) }
      Page.where(skin: name).each { |p| File.write(dir.join("pages", "#{p.name}.txp"), p.user_html) }
      Dir[dir.join("styles", "*.css")].each { |f| FileUtils.rm_f(f) }
      Style.where(skin: name).each { |s| File.write(dir.join("styles", "#{s.name}.css"), s.css) }
      Dir[dir.join("forms", "*", "*.txp")].each { |f| FileUtils.rm_f(f) }
      Form.where(skin: name).each do |f|
        FileUtils.mkdir_p(dir.join("forms", f.type))
        File.write(dir.join("forms", f.type, "#{f.name}.txp"), f.Form)
      end
      dir
    end

    # Builds a .zip archive of a theme and returns its binary contents.
    def zip(name)
      require "zip" if defined?(Zip)
      Dir.mktmpdir do |tmp|
        dir = export(name, File.join(tmp, name))
        out = File.join(tmp, "#{name}.zip")
        system("cd #{Shellwords.escape(tmp)} && zip -qr #{Shellwords.escape(out)} #{Shellwords.escape(name)}") or raise "zip failed"
        _ = dir
        File.binread(out)
      end
    end

    # Unpacks an uploaded .zip theme and imports it.
    def import_zip(path, name: nil)
      Dir.mktmpdir do |tmp|
        system("unzip -qq -o #{Shellwords.escape(path.to_s)} -d #{Shellwords.escape(tmp)}") or raise ArgumentError, "invalid zip"
        manifest = Dir[File.join(tmp, "**", "manifest.json")].min_by(&:length)
        root = manifest ? File.dirname(manifest) : Dir[File.join(tmp, "*")].find { |d| File.directory?(d) } || tmp
        import(root, name: name || Text.sanitize_for_theme(File.basename(root)))
      end
    end

    # Themes available on disk (skin_dir) that can be imported.
    def available_on_disk
      Dir[skin_dir.join("*", "manifest.json")].map { |m| File.basename(File.dirname(m)) }.sort
    end

    # Copies a theme (duplicate).
    def duplicate(name, new_name)
      src = Skin.find(name)
      ActiveRecord::Base.transaction do
        copy = Skin.create!(src.attributes.merge("name" => new_name, "title" => "#{src.title} (copy)", "lastmod" => Time.now.utc))
        Page.where(skin: name).each { |p| Page.create!(name: p.name, skin: new_name, user_html: p.user_html) }
        Form.where(skin: name).each { |f| Form.create!(name: f.name, skin: new_name, type: f.type, Form: f.Form) }
        Style.where(skin: name).each { |s| Style.create!(name: s.name, skin: new_name, css: s.css) }
        copy
      end
    end
  end
end
