class ApplicationMailer < ActionMailer::Base
  default from: -> { txp_sender }
  layout "mailer"

  private

  # txpMail(): from the publisher's address (or no-reply@ the site's host),
  # in the site's name. The smtp_from preference is only the envelope sender
  # (see Txp::MailDelivery).
  def txp_sender
    email = Pref.get("publisher_email").to_s
    email = "no-reply@#{Pref.get('siteurl').to_s.split('/').first.presence || 'localhost'}" unless email.match?(URI::MailTo::EMAIL_REGEXP)
    email_address_with_name(email, Pref.get("sitename").to_s)
  end
end
