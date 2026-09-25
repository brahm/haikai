module Txp
  # String sanitisers (URL titles, file names, page names) and transliteration.
  module Text
    module_function

    TRANSLIT = {
      "À" => "A", "Á" => "A", "Â" => "A", "Ã" => "A", "Ä" => "Ae", "Å" => "A", "Æ" => "Ae", "Ā" => "A", "Ą" => "A", "Ă" => "A",
      "Ç" => "C", "Ć" => "C", "Č" => "C", "Ĉ" => "C", "Ċ" => "C", "Ď" => "D", "Đ" => "D", "Ð" => "D",
      "È" => "E", "É" => "E", "Ê" => "E", "Ë" => "E", "Ē" => "E", "Ę" => "E", "Ě" => "E", "Ĕ" => "E", "Ė" => "E",
      "Ĝ" => "G", "Ğ" => "G", "Ġ" => "G", "Ģ" => "G", "Ĥ" => "H", "Ħ" => "H",
      "Ì" => "I", "Í" => "I", "Î" => "I", "Ï" => "I", "Ī" => "I", "Ĩ" => "I", "Ĭ" => "I", "Į" => "I", "İ" => "I",
      "Ĳ" => "IJ", "Ĵ" => "J", "Ķ" => "K", "Ł" => "L", "Ľ" => "L", "Ĺ" => "L", "Ļ" => "L", "Ŀ" => "L",
      "Ñ" => "N", "Ń" => "N", "Ň" => "N", "Ņ" => "N", "Ŋ" => "N",
      "Ò" => "O", "Ó" => "O", "Ô" => "O", "Õ" => "O", "Ö" => "Oe", "Ø" => "O", "Ō" => "O", "Ő" => "O", "Ŏ" => "O", "Œ" => "OE",
      "Ŕ" => "R", "Ř" => "R", "Ŗ" => "R", "Ś" => "S", "Š" => "S", "Ş" => "S", "Ŝ" => "S", "Ș" => "S",
      "Ť" => "T", "Ţ" => "T", "Ŧ" => "T", "Ț" => "T",
      "Ù" => "U", "Ú" => "U", "Û" => "U", "Ü" => "Ue", "Ū" => "U", "Ů" => "U", "Ű" => "U", "Ŭ" => "U", "Ũ" => "U", "Ų" => "U",
      "Ŵ" => "W", "Ý" => "Y", "Ŷ" => "Y", "Ÿ" => "Y", "Ź" => "Z", "Ž" => "Z", "Ż" => "Z", "Þ" => "T",
      "à" => "a", "á" => "a", "â" => "a", "ã" => "a", "ä" => "ae", "å" => "a", "ā" => "a", "ą" => "a", "ă" => "a", "æ" => "ae",
      "ç" => "c", "ć" => "c", "č" => "c", "ĉ" => "c", "ċ" => "c", "ď" => "d", "đ" => "d", "ð" => "d",
      "è" => "e", "é" => "e", "ê" => "e", "ë" => "e", "ē" => "e", "ę" => "e", "ě" => "e", "ĕ" => "e", "ė" => "e",
      "ƒ" => "f", "ĝ" => "g", "ğ" => "g", "ġ" => "g", "ģ" => "g", "ĥ" => "h", "ħ" => "h",
      "ì" => "i", "í" => "i", "î" => "i", "ï" => "i", "ī" => "i", "ĩ" => "i", "ĭ" => "i", "į" => "i", "ı" => "i",
      "ĳ" => "ij", "ĵ" => "j", "ķ" => "k", "ĸ" => "k", "ł" => "l", "ľ" => "l", "ĺ" => "l", "ļ" => "l", "ŀ" => "l",
      "ñ" => "n", "ń" => "n", "ň" => "n", "ņ" => "n", "ŉ" => "n", "ŋ" => "n",
      "ò" => "o", "ó" => "o", "ô" => "o", "õ" => "o", "ö" => "oe", "ø" => "o", "ō" => "o", "ő" => "o", "ŏ" => "o", "œ" => "oe",
      "ŕ" => "r", "ř" => "r", "ŗ" => "r", "š" => "s", "ś" => "s", "ş" => "s", "ŝ" => "s", "ș" => "s",
      "ť" => "t", "ţ" => "t", "ŧ" => "t", "ț" => "t",
      "ù" => "u", "ú" => "u", "û" => "u", "ü" => "ue", "ū" => "u", "ů" => "u", "ű" => "u", "ŭ" => "u", "ũ" => "u", "ų" => "u",
      "ŵ" => "w", "ý" => "y", "ÿ" => "y", "ŷ" => "y", "ž" => "z", "ż" => "z", "ź" => "z", "þ" => "t", "ß" => "ss", "ſ" => "ss"
    }.freeze

    TRANSLIT_RE = Regexp.union(TRANSLIT.keys)

    def dumb_down(str)
      str.to_s.gsub(TRANSLIT_RE, TRANSLIT)
    end

    def sanitize_for_url(text, strip = /[^\p{L}\p{N}\-_\s\/\\]/u)
      text = dumb_down(Nokogiri::HTML.fragment(text.to_s).text)
      text = text.gsub(strip, "")
      text.gsub(%r{[\s\-/\\]+}, "-").gsub(/\A-+|-+\z/, "")
    end

    # stripSpace(): generates an article URL title.
    def strip_space(text, prefs = {}, force: false)
      return nil unless force || Php.truthy?(prefs.fetch("attach_titles_to_permalinks", "1"))

      text = sanitize_for_url(text, /[^\p{L}\p{N}\-_\s\/\\\u{1F300}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{2600}-\u{27BF}]/u).gsub(/\A-+|-+\z/, "")
      Php.truthy?(prefs.fetch("permlink_format", "1")) ? text.downcase : text.delete("-")
    end

    def sanitize_for_file(text)
      text = text.to_s.gsub(/[\x00-\x1f"*\/:<>?\\|\x7f]+/, "")
      text.strip.gsub(/\A[. ]+|[. ]+\z/, "").gsub(/\.{2,}/, ".")
    end

    def sanitize_for_page(text)
      text.to_s.gsub(/[<>&"']/, "").strip
    end

    def sanitize_for_theme(text)
      sanitize_for_url(text).downcase
    end

    # noWidow(): replaces the last space with a non-breaking one.
    def no_widow(str)
      str.to_s.rstrip.sub(/ +([[:punct:]]?[\p{L}\p{N}\p{Pc}]+[[:punct:]]?)\z/u, "&#160;\\1")
    end
  end
end
