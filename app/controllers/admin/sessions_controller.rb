module Admin
  # Login, logout, password reset and first-run setup (txp_auth.php + setup).
  class SessionsController < BaseController
    skip_before_action :require_login
    skip_before_action :load_admin_plugins

    def handle
      return setup unless User.exists?
      return logout if params[:logout].present?
      return reset_request if params[:reset].present? || params[:p_reset].present?
      return set_password if params[:confirm].present? || params[:activate].present? || params[:p_alter].present? || params[:p_set].present?
      return login if request.post? && params.key?(:p_userid)

      if current_user
        panel = Txp::Plugins.admin_panels[params[:event].to_s]
        return plugin_panel(panel) if panel

        default_event = @prefs["default_event"].presence || "article"
        default_event = "article" unless has_privs?(default_event)
        return redirect_to(admin_url(event: default_event))
      end

      login_form
    end

    private

    def login_form(status: :ok)
      @page_title = gTxt("login")
      @name = cookies[:txp_login_name].to_s
      render "admin/sessions/login", status: status
    end

    def login
      user = User.find_by(name: params[:p_userid].to_s.strip)
      if user && user.privs.to_i.positive? && user.authenticate(params[:p_password].to_s)
        reset_session
        session[:txp_user_id] = user.user_id
        session[:txp_nonce] = user.nonce
        request.session_options[:expire_after] = 1.year if params[:stay].present?
        cookies[:txp_login_name] = { value: user.name, expires: 1.year.from_now, httponly: true } if params[:stay].present?
        user.update_columns(last_access: Time.now.utc.change(usec: 0))
        remember_site_url
        lang = params[:lang].to_s
        Pref.set("language_ui", lang, event: "admin", type: Txp::PREF_HIDDEN, user: user.name) if lang.present? && Txp::Textpack.available.include?(lang)
        Txp::Callbacks.fire("admin_side", "login", user: user)
        target = params[:return_to].to_s
        redirect_to(target.start_with?("/textpattern") ? target : admin_url(event: (@prefs["default_event"].presence || "article")))
      else
        sleep 0.3 unless Rails.env.test?
        announce(gTxt("could_not_log_in"), :error)
        login_form(status: :unauthorized)
      end
    end

    def logout
      if current_user
        current_user.update_columns(nonce: SecureRandom.hex(16))
        Txp::Callbacks.fire("admin_side", "logout", user: current_user)
      end
      reset_session
      cookies.delete(:txp_login_name)
      @current_user = nil
      announce(gTxt("logged_out"), :success)
      login_form
    end

    def reset_request
      @page_title = gTxt("password_reset")
      if request.post? && params[:p_reset].present?
        user = User.find_by(name: params[:p_userid].to_s.strip)
        if user && user.privs.to_i.positive?
          selector = SecureRandom.hex(6)
          secret = SecureRandom.hex(20)
          if (url = emailed_admin_url(lang: lang_ui, confirm: "#{selector}#{secret}"))
            Token.where(reference_id: user.user_id, type: "password_reset").delete_all
            Token.create!(reference_id: user.user_id, type: "password_reset", selector: selector,
              token: Digest::SHA256.hexdigest(secret), expires: 4.hours.from_now.utc.change(usec: 0))
            AdminMailer.password_reset(user, url).deliver_later
            Rails.logger.info("[txp] password reset link for #{user.name}: #{url}") unless Rails.env.production?
          else
            Rails.logger.warn("[txp] password reset for #{user.name} not sent: the site URL is not set (Preferences, Site)")
          end
        end
        # Same message whether or not the user exists (no account enumeration).
        announce(gTxt("password_reset_confirmation_request_sent"), :success)
      end
      render "admin/sessions/reset"
    end

    def set_password
      hash = (params[:confirm].presence || params[:activate].presence || params[:hash]).to_s
      selector = hash[0, 12]
      secret = hash[12..].to_s
      token = Token.where(type: %w[password_reset account_activation], selector: selector).where("expires > ?", Time.now.utc).first
      valid = token && ActiveSupport::SecurityUtils.secure_compare(token.token, Digest::SHA256.hexdigest(secret))
      @hash = hash
      @activate = params[:activate].present? || params[:p_set].present?
      @page_title = gTxt(@activate ? "set_password" : "change_password")

      unless valid
        announce(gTxt("invalid_token"), :error)
        return render("admin/sessions/reset", status: :unprocessable_entity)
      end

      if request.post? && (params[:p_alter].present? || params[:p_set].present?)
        user = User.find_by(user_id: token.reference_id)
        user.password = params[:p_password].to_s
        user.nonce = SecureRandom.hex(16)
        if user.save
          token.destroy
          announce(gTxt("password_changed"), :success)
          return login_form
        end
        announce(user.errors.full_messages.to_sentence, :error)
      end

      render "admin/sessions/password"
    end

    def setup
      @page_title = gTxt("setup")
      @langs = Txp::Textpack.names

      if request.post?
        lang = @langs.key?(params[:lang].to_s) ? params[:lang].to_s : "en"
        user = User.new(name: params[:name].to_s.strip, RealName: params[:RealName].to_s.strip, email: params[:email].to_s.strip,
          privs: 1, password: params[:password].to_s)
        if user.valid?
          Txp::Installer.install!(sitename: params[:sitename].presence || "My site", lang: lang, user: user)
          remember_site_url
          reset_session
          session[:txp_user_id] = user.user_id
          session[:txp_nonce] = user.nonce
          return redirect_with_message(admin_url(event: "article"), gTxt("setup_complete"))
        end
        @user = user
        announce(user.errors.full_messages.to_sentence, :error)
      end

      @user ||= User.new
      render "admin/sessions/setup"
    end

    def plugin_panel(panel)
      @page_title = params[:event].to_s
      @panel_html = panel.call(self).to_s
      render "admin/shared/plugin_panel"
    end

    def event
      params[:event].to_s
    end
  end
end
