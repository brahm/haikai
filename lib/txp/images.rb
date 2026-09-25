require "open3"

module Txp
  # Image storage helpers: dimensions, custom and automatic thumbnails.
  #
  # Images live in public/<img_dir>/<id><ext> and custom thumbnails in
  # public/<img_dir>/<id>t<ext>, exactly like Textpattern, so existing image
  # directories can be copied over as-is.
  module Images
    module_function

    SAFE_TYPES = {
      ".gif" => "image/gif", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".png" => "image/png",
      ".webp" => "image/webp", ".avif" => "image/avif", ".svg" => "image/svg+xml"
    }.freeze

    def mime_for(ext)
      SAFE_TYPES[ext.to_s.downcase] || "application/octet-stream"
    end

    def dir(prefs = Pref.site_prefs)
      Rails.root.join("public", prefs.fetch("img_dir", "images").presence || "images")
    end

    def path(id, ext, thumbnail: false, prefs: Pref.site_prefs)
      dir(prefs).join("#{id}#{thumbnail ? 't' : ''}#{ext}")
    end

    def magick
      return @magick if defined?(@magick)

      @magick = %w[magick convert].find { |bin| system("which #{bin} > /dev/null 2>&1") }
    end

    # Returns [width, height] for an image file (pure Ruby for common types).
    def dimensions(file)
      data = File.binread(file, 64 * 1024)
      return nil if data.nil?

      if data.start_with?("\x89PNG".b)
        data[16, 8].unpack("NN")
      elsif data.start_with?("GIF8".b)
        data[6, 4].unpack("vv")
      elsif data.start_with?("RIFF".b) && data[8, 4] == "WEBP".b
        webp_dimensions(data)
      elsif data.start_with?("\xFF\xD8".b)
        jpeg_dimensions(file)
      elsif data.lstrip.start_with?("<".b) && data.include?("<svg".b)
        svg_dimensions(File.read(file))
      else
        magick_dimensions(file)
      end
    rescue StandardError
      nil
    end

    def webp_dimensions(data)
      case data[12, 4]
      when "VP8 ".b
        w, h = data[26, 4].unpack("vv")
        [ w & 0x3fff, h & 0x3fff ]
      when "VP8L".b
        b = data[21, 4].unpack("C4")
        [ 1 + (((b[1] & 0x3F) << 8) | b[0]), 1 + (((b[3] & 0xF) << 10) | (b[2] << 2) | ((b[1] & 0xC0) >> 6)) ]
      when "VP8X".b
        w = data[24, 3].unpack("C3")
        h = data[27, 3].unpack("C3")
        [ 1 + (w[0] | (w[1] << 8) | (w[2] << 16)), 1 + (h[0] | (h[1] << 8) | (h[2] << 16)) ]
      end
    end

    def jpeg_dimensions(file)
      File.open(file, "rb") do |io|
        io.read(2)
        loop do
          marker = io.read(2)&.unpack("CC")
          return nil if marker.nil? || marker[0] != 0xFF

          code = marker[1]
          length = io.read(2).unpack1("n")
          if (0xC0..0xCF).cover?(code) && ![ 0xC4, 0xC8, 0xCC ].include?(code)
            io.read(1)
            h, w = io.read(4).unpack("nn")
            return [ w, h ]
          end
          io.seek(length - 2, IO::SEEK_CUR)
        end
      end
    end

    def svg_dimensions(xml)
      doc = Nokogiri::XML(xml)
      svg = doc.at_xpath("//*[local-name()='svg']")
      return [ 0, 0 ] unless svg

      w = svg["width"].to_f
      h = svg["height"].to_f
      if (w.zero? || h.zero?) && svg["viewBox"]
        _, _, vw, vh = svg["viewBox"].split(/[\s,]+/).map(&:to_f)
        w = vw if w.zero?
        h = vh if h.zero?
      end
      [ w.round, h.round ]
    end

    def magick_dimensions(file)
      return nil unless magick

      out, status = Open3.capture2(magick == "magick" ? "magick" : "identify", *(magick == "magick" ? [ "identify" ] : []), "-format", "%w %h", "#{file}[0]")
      status.success? ? out.split.map(&:to_i) : nil
    end

    # Resizes src into dest. crop: "1x1", "4x3", true...; returns [w, h] or nil.
    def resize(src, dest, width: nil, height: nil, crop: nil, quality: nil)
      return nil unless magick

      width = width.to_i
      height = height.to_i
      args = [ src.to_s + "[0]", "-auto-orient" ]

      if crop.present? && crop.to_s != "0"
        ratio = crop.to_s.split(/[x:]/).map(&:to_f)
        ratio = [ 1.0, 1.0 ] if ratio.length < 2 || ratio.any?(&:zero?)
        if width.positive? && height.zero?
          height = (width * ratio[1] / ratio[0]).round
        elsif height.positive? && width.zero?
          width = (height * ratio[0] / ratio[1]).round
        elsif width.zero? && height.zero?
          width = height = 100
        end
        args += [ "-resize", "#{width}x#{height}^", "-gravity", "center", "-extent", "#{width}x#{height}" ]
      elsif width.positive? || height.positive?
        args += [ "-resize", "#{width.positive? ? width : ''}x#{height.positive? ? height : ''}>" ]
      end

      args += [ "-quality", quality.to_i.clamp(1, 100).to_s ] if quality.to_i.positive?
      args += [ "-strip", dest.to_s ]
      FileUtils.mkdir_p(File.dirname(dest))
      cmd = magick == "magick" ? [ "magick", *args ] : [ "convert", *args ]
      _out, status = Open3.capture2e(*cmd)
      status.success? ? dimensions(dest) : nil
    end
  end
end
