require "test_helper"

class Txp::MailDeliveryTest < ActiveSupport::TestCase
  setup { TxpTestSite.install! }

  def prefs(extra = {})
    Pref.site_prefs.merge(extra)
  end

  test "SMTP needs enhanced email plus a host and a port" do
    assert_nil Txp::MailDelivery.smtp_settings(prefs("smtp_host" => "mail.example.com", "smtp_port" => "587"), {})
    assert_nil Txp::MailDelivery.smtp_settings(prefs("enhanced_email" => "1", "smtp_host" => "mail.example.com"), {})

    smtp = Txp::MailDelivery.smtp_settings(prefs("enhanced_email" => "1", "smtp_host" => "mail.example.com", "smtp_port" => "587"), {})
    assert_equal({ address: "mail.example.com", port: 587, enable_starttls_auto: true }, smtp)
  end

  test "SMTP credentials and security type" do
    base = { "enhanced_email" => "1", "smtp_host" => "mail.example.com", "smtp_port" => "465", "smtp_user" => "me", "smtp_pass" => "secret" }
    smtp = Txp::MailDelivery.smtp_settings(prefs(base.merge("smtp_sectype" => "ssl")), {})
    assert_equal [ "me", "secret", true ], smtp.values_at(:user_name, :password, :tls)
    assert Txp::MailDelivery.smtp_settings(prefs(base.merge("smtp_sectype" => "tls")), {})[:enable_starttls]
    none = Txp::MailDelivery.smtp_settings(prefs(base.merge("smtp_sectype" => "none")), {})
    assert_equal [ false, "none" ], none.values_at(:enable_starttls_auto, :openssl_verify_mode)
  end

  test "SMTP_* environment variables take precedence" do
    env = { "SMTP_HOST" => "relay.example.net", "SMTP_PORT" => "2525", "SMTP_USER" => "env-user", "SMTP_PASS" => "env-pass" }
    smtp = Txp::MailDelivery.smtp_settings(prefs("enhanced_email" => "1", "smtp_host" => "mail.example.com", "smtp_port" => "587"), env)
    assert_equal [ "relay.example.net", 2525, "env-user", "env-pass" ], smtp.values_at(:address, :port, :user_name, :password)
    assert Txp::MailDelivery.overridden?("smtp_host", env)
    assert_not Txp::MailDelivery.overridden?("smtp_from", env)
  end

  test "transport is SMTP or sendmail" do
    delivery = Txp::MailDelivery.new
    assert_kind_of Mail::Sendmail, delivery.transport(prefs)
    assert_kind_of Mail::SMTP, delivery.transport(prefs("enhanced_email" => "1", "smtp_host" => "h", "smtp_port" => "25"))
  end

  test "envelope sender and ISO-8859-1 bodies" do
    Pref.set("smtp_from", "Bounces <bounces@example.com>", event: "mail")
    Pref.set("override_emailcharset", "1", event: "mail")
    sent = nil
    transport = Object.new
    transport.define_singleton_method(:deliver!) { |message| sent = message }
    delivery = Txp::MailDelivery.new
    delivery.define_singleton_method(:transport) { |_prefs| transport }

    message = Mail.new(to: "a@example.com", from: "b@example.com", subject: "Olá", body: "Comentário recebido", charset: "UTF-8")
    delivery.deliver!(message)
    assert_equal "bounces@example.com", sent.smtp_envelope_from
    assert_equal "ISO-8859-1", sent.charset
    assert_equal "Comentário recebido".encode("ISO-8859-1").b, sent.body.decoded.b
  end

  test "mail comes from the publisher address in the site's name" do
    Pref.set("publisher_email", "editor@example.com", event: "mail")
    user = User.find_by(name: "alice")
    mail = AdminMailer.password_reset(user, "http://example.com/reset")
    assert_equal [ "editor@example.com" ], mail.from
    assert_equal "My site <editor@example.com>", mail[:from].value

    Pref.set("publisher_email", "", event: "mail")
    assert_equal [ "no-reply@localhost" ], AdminMailer.password_reset(user, "http://example.com/reset").from
  end

  test "mail jobs, which carry reset links, are logged without arguments" do
    assert_not ActionMailer::MailDeliveryJob.log_arguments?
  end
end
