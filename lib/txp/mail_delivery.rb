require "mail"

module Txp
  # ActionMailer delivery method (:textpattern) following Textpattern's mail
  # preferences (\Textpattern\Mail\Adapter\SMTPMail and Mail): SMTP when "Use
  # enhanced mail features" is on and a host and port are set, the local
  # sendmail otherwise. SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS and
  # SMTP_SECTYPE environment variables take precedence over the preferences,
  # like the SMTP_* constants of Textpattern's config.php.
  class MailDelivery
    ENV_KEYS = %w[smtp_host smtp_port smtp_user smtp_pass smtp_sectype].freeze

    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
    end

    def deliver!(message)
      prefs = Pref.site_prefs
      # "SMTP envelope sender address"
      envelope = prefs["smtp_from"].to_s[/[^<>\s]+@[^<>\s]+/]
      message.smtp_envelope_from = envelope if envelope
      latin1!(message) if Php.truthy?(prefs["override_emailcharset"])
      transport(prefs).deliver!(message)
    end

    def transport(prefs)
      if (smtp = self.class.smtp_settings(prefs))
        Mail::SMTP.new(smtp)
      else
        Mail::Sendmail.new(settings.slice(:location, :arguments))
      end
    end

    # The value of an SMTP preference, or of its environment variable.
    def self.setting(prefs, name, env = ENV)
      env[name.upcase].presence || prefs[name].to_s
    end

    def self.overridden?(name, env = ENV)
      ENV_KEYS.include?(name) && env[name.upcase].present?
    end

    def self.smtp_settings(prefs, env = ENV)
      host = setting(prefs, "smtp_host", env)
      port = setting(prefs, "smtp_port", env).to_i
      return unless Php.truthy?(prefs["enhanced_email"]) && host.present? && port.positive?

      smtp = { address: host, port: port }
      user = setting(prefs, "smtp_user", env)
      smtp.merge!(user_name: user, password: setting(prefs, "smtp_pass", env)) if user.present?
      case setting(prefs, "smtp_sectype", env)
      when "ssl" then smtp[:tls] = true # SMTPS
      when "tls" then smtp[:enable_starttls] = true
      when "none" then smtp.merge!(enable_starttls_auto: false, openssl_verify_mode: "none")
      else smtp[:enable_starttls_auto] = true # PHPMailer's SMTPAutoTLS
      end
      smtp
    end

    # "Use ISO-8859-1 encoding in emails".
    def latin1!(message)
      parts = message.multipart? ? message.all_parts.reject(&:multipart?) : [ message ]
      parts.each do |part|
        next unless (part.mime_type || "text/plain").start_with?("text/")

        text = part.decoded.encode("ISO-8859-1", invalid: :replace, undef: :replace, replace: "?")
        part.charset = "ISO-8859-1"
        part.body = text
      end
    end
  end
end
