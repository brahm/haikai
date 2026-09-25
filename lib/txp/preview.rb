module Txp
  # Signed tokens for previewing unpublished articles from the admin side.
  module Preview
    module_function

    def token(user, id)
      return "" unless user

      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "preview:#{user.name}:#{user.nonce}:#{id}")[0, 32]
    end

    def url(renderer_hu, user, id)
      "#{renderer_hu}?id=#{id}.#{token(user, id)}"
    end
  end
end
