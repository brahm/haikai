class ApplicationController < ActionController::Base
  helper_method :current_user

  private

  # The logged-in admin user (shared with the public side, like Textpattern's
  # txp_login_public cookie).
  def current_user
    return @current_user if defined?(@current_user)

    @current_user = if session[:txp_user_id]
      user = User.find_by(user_id: session[:txp_user_id])
      user if user && user.nonce == session[:txp_nonce] && user.privs.to_i.positive?
    end
  end
end
