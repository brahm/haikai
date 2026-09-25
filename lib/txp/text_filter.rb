module Txp
  # Article text filters: Textile (RedCloth), line-break conversion and raw.
  module TextFilter
    module_function

    FILTERS = {
      LEAVE_TEXT_UNTOUCHED => "leave_text_untouched",
      USE_TEXTILE => "use_textile",
      CONVERT_LINEBREAKS => "convert_linebreaks"
    }.freeze


    def apply(text, filter)
      case filter.to_s
      when USE_TEXTILE then textile(text)
      when CONVERT_LINEBREAKS then nl2br(text.to_s.strip)
      else text.to_s
      end
    end

    def nl2br(text)
      text.gsub(/(\r\n|\n|\r)/) { "<br />#{Regexp.last_match(1)}" }
    end

    # Textile conversion. RedCloth passes <txp:...> tags through untouched
    # (and escapes them inside code spans), like php-textile does.
    def textile(text, restricted: false, lite: false, noimage: false, rel: nil)
      text = text.to_s
      return "" if text.strip.empty?

      options = []
      options += %i[filter_html filter_styles filter_classes filter_ids] if restricted
      options << :lite_mode if lite
      html = RedCloth.new(text, options).to_html
      html = html.gsub(/<img[^>]*>/i, "") if noimage
      html = html.gsub(/<a (?![^>]*\brel=)/i, %(<a rel="#{rel}" )) if rel.to_s != ""

      if lite
        html = html.strip
        html = html.sub(%r{\A<p>(.*)</p>\z}m, '\1') if html.scan("<p>").length == 1
      end
      html
    end

    # Comment markup (restricted Textile, like markup_comment()).
    def comment(text, prefs = {})
      textile(text, restricted: true, lite: false,
        noimage: Php.truthy?(prefs["comments_disallow_images"]),
        rel: Php.truthy?(prefs["comment_nofollow"]) ? "nofollow" : nil)
    end
  end
end
