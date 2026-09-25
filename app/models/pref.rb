# Preferences (txp_prefs). Global prefs have user_name = ''.
class Pref < ApplicationRecord
  self.table_name = "txp_prefs"
  self.primary_key = [ :name, :user_name ]
  self.inheritance_column = :_type_disabled

  scope :global, -> { where(user_name: "") }

  class << self
    # Site-wide preferences as a Hash (cached per request/thread briefly).
    def site_prefs(user = nil)
      prefs = global.pluck(:name, :val).to_h
      if user
        where(user_name: user.to_s).pluck(:name, :val).each { |n, v| prefs[n] = v }
      end
      prefs
    end

    def get(name, default = nil, user: "")
      where(name: name.to_s, user_name: user.to_s).pick(:val) || default
    end

    def set(name, val, event: "publish", type: Txp::PREF_CORE, html: "text_input", position: 0, user: "")
      rec = find_or_initialize_by(name: name.to_s, user_name: user.to_s)
      if rec.new_record?
        rec.assign_attributes(event: event, type: type, html: html, position: position)
      end
      rec.val = val.to_s
      rec.save!
      rec
    end

    def touch_lastmod!
      set("lastmod", Time.now.utc.strftime("%Y-%m-%d %H:%M:%S"), type: Txp::PREF_HIDDEN)
    end
  end
end
