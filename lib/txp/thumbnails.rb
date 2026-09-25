module Txp
  # Automatic ("dynamic") thumbnails: /images/thumb/w200-h200-c1x1/12.jpg
  module Thumbnails
    module_function

    def encode(params)
      params.map { |k, v| "#{k}#{v}" }.join("-")
    end

    def decode(str)
      str.to_s.split("-").each_with_object({}) do |part, h|
        key = part[0]
        h[key] = part[1..] if %w[w h c q t b].include?(key)
      end
    end

    def secret(prefs)
      prefs["thumb_secret"].presence || Rails.application.secret_key_base.to_s[0, 32]
    end

    def token(id, paramlist, prefs)
      OpenSSL::HMAC.hexdigest("SHA256", secret(prefs), "#{id}#{paramlist}")
    end

    def token_query(id, params, prefs)
      return "" if params.empty?

      "?token=#{token(id, encode(params), prefs)}"
    end
  end
end
