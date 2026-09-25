# Emails sent from the admin side (password reset, new account activation).
class AdminMailer < ApplicationMailer
  def password_reset(user, url)
    lang = Pref.get("language_ui", "en", user: user.name) || "en"
    @url = url
    @user = user
    @body = Txp::Textpack.txt(lang, "password_reset_email", { "{name}" => user.display_name, "{url}" => url }, "")
    mail(to: user.email, from: sender, subject: "[#{Pref.get('sitename')}] #{Txp::Textpack.txt(lang, 'password_reset')}") do |format|
      format.text { render plain: @body }
    end
  end

  def account_activation(user, url)
    lang = Pref.get("language_ui", "en") || "en"
    @body = Txp::Textpack.txt(lang, "account_activation_email", { "{name}" => user.display_name, "{username}" => user.name, "{url}" => url, "{sitename}" => Pref.get("sitename").to_s }, "")
    mail(to: user.email, from: sender, subject: "[#{Pref.get('sitename')}] #{Txp::Textpack.txt(lang, 'account_activation')}") do |format|
      format.text { render plain: @body }
    end
  end

  private

  def sender
    Pref.get("smtp_from").presence || Pref.get("publisher_email").presence || "noreply@#{Pref.get('siteurl').presence || 'localhost'}"
  end
end
