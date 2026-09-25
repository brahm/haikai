module Admin
  # The Preferences panel (event=prefs).
  class PrefsController < BaseController
    self.event_name = "prefs"
    self.default_step = :index

    step "prefs_list", :index
    step "prefs_save", :save, post: true

    GROUPS = %w[site admin publish feeds comments custom mail advanced_options].freeze

    private

    def index
      @page_title = gTxt("tab_preferences")
      @group = GROUPS.include?(params[:group]) ? params[:group] : "site"
      @prefs_by_group = Pref.global.where(type: [ Txp::PREF_CORE, Txp::PREF_PLUGIN ]).order(:position, :name).to_a.group_by(&:event)
      @groups = GROUPS + (@prefs_by_group.keys - GROUPS).sort
      render "admin/prefs/index"
    end

    def save
      return require_privs!("prefs.edit") unless has_privs?("prefs.edit")

      group = params[:group].to_s
      values = params.fetch(:prefs, {}).to_unsafe_h
      Pref.global.where(type: [ Txp::PREF_CORE, Txp::PREF_PLUGIN ], event: group).find_each do |pref|
        next unless values.key?(pref.name)

        value = values[pref.name]
        # The SMTP password is never printed back, so a blank one keeps it.
        next if pref.name == "smtp_pass" && value.blank?

        value = Array(value).reject(&:blank?).join(",") if pref.html == "overrideTypes"
        value = value.to_s
        value = normalize_value(pref, value)
        pref.update!(val: value) if pref.val != value
      end

      if values.key?("timezone_key")
        tz = values["timezone_key"].to_s
        Pref.set("timezone_key", tz, type: Txp::PREF_HIDDEN) if ActiveSupport::TimeZone[tz]
      end

      Txp::Textpack.reset!
      Pref.touch_lastmod!
      redirect_with_message(admin_url(event: "prefs", group: group), gTxt("preferences_saved"))
    end

    def normalize_value(pref, value)
      case pref.name
      when "siteurl" then value.sub(%r{\Ahttps?://}, "").chomp("/")
      when "img_dir", "skin_dir" then value.gsub(%r{[^\w\-/]}, "").gsub(%r{\A/+|/+\z}, "").presence || pref.val
      else value
      end
    end
  end
end
