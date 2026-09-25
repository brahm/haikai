module Txp
  module Tags
    # Privacy tags: <txp:if_logged_in /> and <txp:password_protect />.
    module Privacy
      def tag_if_logged_in(atts, thing = nil)
        a = lAtts({ "group" => "", "name" => "" }, atts)
        user = logged_in_user
        user = nil if user && Php.truthy?(a["name"]) && !Php.in_list(user["name"], a["name"])
        x = if user && Php.str(a["group"]) != ""
          privs = Php.do_list(a["group"]).map { |p| Php.numeric?(p) ? p.to_i : (GROUPS.key(p) || -1) }.uniq
          privs.include?(user["privs"].to_i)
        else
          !user.nil?
        end
        thing.nil? ? x : parse(thing, x)
      end

      def tag_password_protect(atts, thing = nil)
        a = lAtts({ "login" => nil, "pass" => nil, "privs" => nil }, atts)

        access = if a["pass"].nil?
          user = logged_in_user
          user = nil if user && !a["login"].nil? && user["name"] != a["login"]
          !user.nil? && (a["privs"].nil? || Php.in_list(user["privs"], a["privs"]))
        else
          au, ap = basic_auth_credentials
          au == Php.str(a["login"]) && ap == Php.str(a["pass"])
        end

        @response_headers["www-authenticate"] = 'Basic realm="Private"' if !access && !a["pass"].nil?

        if thing.nil?
          txp_die(gTxt("auth_required"), "401") unless access
          return ""
        end

        parse(thing, access)
      end

      def basic_auth_credentials
        return [ nil, nil ] unless @request

        auth = @request.authorization.to_s
        return [ nil, nil ] unless auth.start_with?("Basic ")

        Base64.decode64(auth.sub("Basic ", "")).split(":", 2)
      end
    end
  end
end
