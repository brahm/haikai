# Textpattern-compatible template engine and CMS core.
#
# The Txp namespace hosts everything needed to render Textpattern templates
# (pages, forms and styles built from <txp:tag /> markup): the tokenizer, the
# parser with global attribute support, the tag library, URL schemes and the
# request router ("pretext").
module Txp
  # The Textpattern code this port mirrors (the 4.9.x branch after 4.9.1).
  VERSION = "4.9.2-dev"

  STATUS_DRAFT = 1
  STATUS_HIDDEN = 2
  STATUS_PENDING = 3
  STATUS_LIVE = 4
  STATUS_STICKY = 5

  STATUSES = {
    STATUS_DRAFT => "draft",
    STATUS_HIDDEN => "hidden",
    STATUS_PENDING => "pending",
    STATUS_LIVE => "live",
    STATUS_STICKY => "sticky"
  }.freeze

  # Comment visibility.
  SPAM = -1
  MODERATE = 0
  VISIBLE = 1
  RELOAD = -99

  # Text filters.
  LEAVE_TEXT_UNTOUCHED = "0"
  USE_TEXTILE = "1"
  CONVERT_LINEBREAKS = "2"

  # Thumbnail kinds.
  THUMB_NONE = "0"
  THUMB_CUSTOM = "1"
  THUMB_AUTO = "2"

  # Preference types.
  PREF_CORE = 0
  PREF_PLUGIN = 1
  PREF_HIDDEN = 2
  PREF_THEME = 3

  # User groups (privileges).
  GROUPS = {
    0 => "none",
    1 => "publisher",
    2 => "managing_editor",
    3 => "copy_editor",
    4 => "staff_writer",
    5 => "freelancer",
    6 => "designer"
  }.freeze

  HTML5_VOID_TAGS = %w[area base br col embed hr img input link meta source track wbr].freeze

  THEME_TREE = { "forms" => "forms", "pages" => "pages", "styles" => "styles" }.freeze

  FORM_TYPES = %w[article misc comment category file link section].freeze

  class TagError < StandardError; end

  # Raised by handle_lastmod() when the client's cached copy is fresh.
  class NotModified < StandardError; end

  # Raised to abort page rendering and produce an HTTP response (txp_die).
  class Die < StandardError
    attr_reader :status, :url

    def initialize(message, status = "503", url = "")
      super(message.to_s)
      @status = status.to_s
      @url = url.to_s
    end
  end

  # Raised to redirect (e.g. after a comment is saved).
  class Redirect < StandardError
    attr_reader :location, :status

    def initialize(location, status = 302)
      super(location)
      @location = location
      @status = status
    end
  end

  class << self
    def sanitize_for_url_title(text, prefs = {})
      Text.strip_space(text, prefs, force: true)
    end

    def zone(prefs)
      key = prefs["timezone_key"].to_s
      (key != "" && ActiveSupport::TimeZone[key]) || ActiveSupport::TimeZone["UTC"]
    end

    # Definitive site URL ("hu"), always ending with a slash.
    def site_url(prefs, request = nil)
      if request && !(Rails.env.production? && prefs["siteurl"].to_s != "")
        "#{request.protocol}#{request.host_with_port}#{request.script_name}/"
      else
        url = prefs["siteurl"].to_s.sub(%r{\Ahttps?://}, "").chomp("/")
        url = "localhost:3000" if url == ""
        proto = prefs["@protocol"] || request&.protocol || (Rails.env.production? ? "https://" : "http://")
        "#{proto}#{url}/"
      end
    end
  end

  def self.root
    Rails.root
  end
end
