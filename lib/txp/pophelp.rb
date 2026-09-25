module Txp
  # Inline help topics ("pophelp") read from Textpattern's own
  # lang/<lang>_pophelp.xml files, bundled in config/textpacks/pophelp
  # (port of \Textpattern\Module\Help\HelpAdmin::pophelp()).
  module Pophelp
    module_function

    DIR = -> { Rails.root.join("config", "textpacks", "pophelp") }

    def document(lang)
      @documents ||= Concurrent::Map.new
      @documents.compute_if_absent(lang.to_s) do
        path = DIR.call.join("#{lang}_pophelp.xml")
        path.exist? ? Nokogiri::XML(File.read(path, encoding: "UTF-8")) : false
      end
    end

    def valid_key?(key)
      key.to_s != "" && !key.to_s.match?(/[^\w:]/)
    end

    # Help for +key+ in +lang+ (falling back to English):
    # { title:, html: } or nil.
    def topic(key, lang)
      return nil unless valid_key?(key)

      key = key.to_s.split(":").last
      [ Textpack.normalize(lang), "en" ].uniq.each do |code|
        node = document(code) && document(code).at_xpath("//item[@id='#{key}']")
        next unless node && node.text.strip != ""

        text = node.text.strip
        html = node["format"] == "textile" ? RedCloth.new(text).to_html : text
        return { title: node["title"].to_s, html: html }
      end
      nil
    end

    def exists?(key, lang = "en")
      !topic(key, lang).nil?
    end
  end
end
