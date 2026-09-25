module Txp
  # Admin-side themes, stored like Textpattern's textpattern/admin-themes:
  #
  #   public/textpattern/admin-themes/<name>/manifest.json
  #   public/textpattern/admin-themes/<name>/assets/css/textpattern.css
  #   public/textpattern/admin-themes/<name>/assets/js/main.js   (optional)
  #
  # The admin markup mirrors Textpattern's, so Textpattern admin theme
  # stylesheets (e.g. Hive or Classic) can be dropped in.
  class AdminTheme
    DEFAULT = "nova".freeze

    attr_reader :name, :manifest

    def self.dir
      Rails.root.join("public", "textpattern", "admin-themes")
    end

    def self.all
      Dir[dir.join("*", "manifest.json")].sort.filter_map do |m|
        theme = new(File.basename(File.dirname(m)))
        theme if theme.manifest["txp-type"].to_s.include?("admin-theme") || theme.manifest["txp-type"].nil?
      end
    end

    def self.find(name)
      name = name.to_s
      name = DEFAULT if name.empty? || !dir.join(name, "manifest.json").exist?
      new(name)
    end

    def initialize(name)
      @name = name
      path = self.class.dir.join(name, "manifest.json")
      @manifest = path.exist? ? (JSON.parse(File.read(path)) rescue {}) : {}
    end

    def title
      manifest["title"].presence || name
    end

    def url
      "/textpattern/admin-themes/#{name}/"
    end

    def asset?(path)
      self.class.dir.join(name, path).exist?
    end

    def stylesheets
      %w[assets/css/textpattern.css].select { |p| asset?(p) }.map { |p| url + p }
    end

    def print_stylesheet
      asset?("assets/css/print.css") ? "#{url}assets/css/print.css" : nil
    end

    # Deferred scripts loaded in <head> after jQuery (Hive: main.js and
    # autosize.js); a manifest "scripts" list overrides the defaults.
    def scripts
      list = Array(manifest["scripts"]).presence || %w[assets/js/main.js assets/js/autosize.js]
      list.select { |p| asset?(p) }.map { |p| url + p }
    end

    # Scripts run at the top of <body> (Hive's darkmode.js).
    def body_scripts
      list = Array(manifest["body_scripts"]).presence || %w[assets/js/darkmode.js]
      list.select { |p| asset?(p) }.map { |p| url + p }
    end

    def favicon
      asset?("assets/img/favicon.ico") ? "#{url}assets/img/favicon.ico" : nil
    end
  end
end
