module Txp
  # Default preferences: Textpattern's core preference set, without those of
  # features left out of this project (the XML-RPC server, plugins)
  # (name => [value, type, event, html widget, position, private]).
  module DefaultPrefs
    LIST = {
      # site
      "sitename" => [ "My site", 0, "site", "text_input", 20 ],
      "siteurl" => [ "", 0, "site", "text_input", 40 ],
      "site_slogan" => [ "My pithy slogan", 0, "site", "text_input", 60 ],
      "production_status" => [ "testing", 0, "site", "prod_levels", 80 ],
      "gmtoffset" => [ "", 0, "site", "gmtoffset_select", 110 ],
      "auto_dst" => [ "0", 0, "site", "yesnoradio", 115 ],
      "is_dst" => [ "0", 0, "site", "is_dst", 120 ],
      "dateformat" => [ "since", 0, "site", "dateformats", 140 ],
      "archive_dateformat" => [ "%b %d, %I:%M %p", 0, "site", "dateformats", 160 ],
      "permlink_mode" => [ "section_title", 0, "site", "permlinkmodes", 180 ],
      "trailing_slash" => [ "0", 0, "site", "trailing_slash", 185 ],
      "doctype" => [ "html5", 0, "site", "doctypes", 190 ],
      "logging" => [ "none", 0, "site", "logging", 220 ],
      "expire_logs_after" => [ "7", 0, "site", "number", 230 ],
      "use_comments" => [ "1", 0, "site", "yesnoradio", 240 ],
      # admin
      "img_dir" => [ "images", 0, "admin", "text_input", 20 ],
      "skin_dir" => [ "themes", 0, "admin", "text_input", 30 ],
      "file_base_path" => [ "", 0, "admin", "text_input", 40 ],
      "file_max_upload_size" => [ "2000000", 0, "admin", "text_input", 60 ],
      "tempdir" => [ "", 0, "admin", "text_input", 80 ],
      "default_event" => [ "article", 0, "admin", "default_event", 150 ],
      "theme_name" => [ "nova", 0, "admin", "themename", 160 ],
      "module_pophelp" => [ "1", 0, "admin", "module_pophelp", 170 ],
      "enable_dev_preview" => [ "1", 0, "admin", "yesnoradio", 180 ],
      "advanced_options" => [ "0", 0, "admin", "onoffradio", 200 ],
      # mail
      "smtp_from" => [ "", 0, "mail", "text_input", 110 ],
      "publisher_email" => [ "", 0, "mail", "text_input", 115 ],
      "override_emailcharset" => [ "0", 0, "mail", "yesnoradio", 120 ],
      "enhanced_email" => [ "0", 0, "mail", "enhanced_email", 150 ],
      "smtp_host" => [ "", 0, "mail", "smtp_handler", 160 ],
      "smtp_port" => [ "", 0, "mail", "smtp_handler", 170 ],
      "smtp_user" => [ "", 0, "mail", "smtp_handler", 180 ],
      "smtp_pass" => [ "", 0, "mail", "smtp_handler", 190 ],
      "smtp_sectype" => [ "", 0, "mail", "smtp_handler", 200 ],
      # comments
      "comments_on_default" => [ "0", 0, "comments", "yesnoradio", 20 ],
      "comments_default_invite" => [ "Comment", 0, "comments", "text_input", 40 ],
      "comments_moderate" => [ "1", 0, "comments", "yesnoradio", 60 ],
      "comments_disabled_after" => [ "42", 0, "comments", "weeks", 80 ],
      "comments_auto_append" => [ "0", 0, "comments", "yesnoradio", 100 ],
      "comments_mode" => [ "0", 0, "comments", "commentmode", 120 ],
      "comments_dateformat" => [ "%b %d, %I:%M %p", 0, "comments", "dateformats", 140 ],
      "comments_sendmail" => [ "0", 0, "comments", "commentsendmail", 160 ],
      "comments_are_ol" => [ "1", 0, "comments", "yesnoradio", 180 ],
      "comment_means_site_updated" => [ "1", 0, "comments", "yesnoradio", 200 ],
      "comments_require_name" => [ "1", 0, "comments", "yesnoradio", 220 ],
      "comments_require_email" => [ "1", 0, "comments", "yesnoradio", 240 ],
      "never_display_email" => [ "1", 0, "comments", "yesnoradio", 260 ],
      "comment_nofollow" => [ "1", 0, "comments", "yesnoradio", 280 ],
      "comments_disallow_images" => [ "0", 0, "comments", "yesnoradio", 300 ],
      "comments_use_fat_textile" => [ "0", 0, "comments", "yesnoradio", 320 ],
      "spam_blocklists" => [ "", 0, "comments", "text_input", 340 ],
      # custom fields
      "custom_1_set" => [ "custom1", 0, "custom", "custom_set", 1 ],
      "custom_2_set" => [ "custom2", 0, "custom", "custom_set", 2 ],
      "custom_3_set" => [ "", 0, "custom", "custom_set", 3 ],
      "custom_4_set" => [ "", 0, "custom", "custom_set", 4 ],
      "custom_5_set" => [ "", 0, "custom", "custom_set", 5 ],
      "custom_6_set" => [ "", 0, "custom", "custom_set", 6 ],
      "custom_7_set" => [ "", 0, "custom", "custom_set", 7 ],
      "custom_8_set" => [ "", 0, "custom", "custom_set", 8 ],
      "custom_9_set" => [ "", 0, "custom", "custom_set", 9 ],
      "custom_10_set" => [ "", 0, "custom", "custom_set", 10 ],
      # feeds
      "syndicate_body_or_excerpt" => [ "1", 0, "feeds", "yesnoradio", 20 ],
      "rss_how_many" => [ "5", 0, "feeds", "number", 40 ],
      "show_comment_count_in_feed" => [ "1", 0, "feeds", "yesnoradio", 60 ],
      "include_email_atom" => [ "0", 0, "feeds", "yesnoradio", 80 ],
      "use_mail_on_feeds_id" => [ "0", 0, "feeds", "yesnoradio", 100 ],
      # publish
      "default_publish_status" => [ "4", 0, "publish", "defaultPublishStatus", 15 ],
      "articles_use_excerpts" => [ "1", 0, "publish", "yesnoradio", 40 ],
      "allow_form_override" => [ "1", 0, "publish", "yesnoradio", 60 ],
      "override_form_types" => [ "article", 0, "publish", "overrideTypes", 70 ],
      "attach_titles_to_permalinks" => [ "1", 0, "publish", "yesnoradio", 80 ],
      "permlink_format" => [ "1", 0, "publish", "permlink_format", 100 ],
      "send_lastmod" => [ "1", 0, "publish", "yesnoradio", 120 ],
      "publish_expired_articles" => [ "0", 0, "publish", "yesnoradio", 130 ],
      "use_textile" => [ "1", 0, "publish", "pref_text", 200 ],
      "enable_short_tags" => [ "1", 0, "publish", "yesnoradio", 230 ],
      "allow_page_php_scripting" => [ "0", 0, "publish", "yesnoradio", 300 ],
      "allow_article_php_scripting" => [ "0", 0, "publish", "yesnoradio", 320 ],
      "max_url_len" => [ "1000", 0, "publish", "number", 340 ],
      # advanced
      "txp_evaluate_functions" => [ "", 0, "advanced_options", "text_input", 100 ],
      "custom_form_types" => [ ";[js]\n;mediatype=\"application/javascript\"\n;title=\"JavaScript\"", 0, "advanced_options", "longtext_input", 200 ],
      "file_download_header" => [ "", 0, "advanced_options", "longtext_input", 250 ],
      "secondpass" => [ "1", 0, "advanced_options", "number", 300 ],
      "concurrent_logins" => [ "", 0, "advanced_options", "text_input", 350 ],
      # hidden
      "blog_mail_uid" => [ "", 2, "publish", "text_input", 0 ],
      "blog_time_uid" => [ "2005", 2, "publish", "text_input", 0 ],
      "blog_uid" => [ "", 2, "publish", "text_input", 0 ],
      "dbupdatetime" => [ "0", 2, "publish", "text_input", 0 ],
      "language" => [ "en", 2, "publish", "text_input", 0 ],
      "language_ui" => [ "en", 2, "admin", "text_input", 0 ],
      "lastmod" => [ "2005-07-23 16:24:10", 2, "publish", "text_input", 0 ],
      "locale" => [ "", 2, "publish", "text_input", 0 ],
      "path_from_root" => [ "/", 2, "publish", "text_input", 0 ],
      "path_to_site" => [ "", 2, "publish", "text_input", 0 ],
      "searchable_article_fields" => [ "Title, Body", 2, "publish", "text_input", 0 ],
      "textile_updated" => [ "1", 2, "publish", "text_input", 0 ],
      "timeoffset" => [ "0", 2, "publish", "text_input", 0 ],
      "timezone_key" => [ "UTC", 2, "publish", "text_input", 0 ],
      "url_mode" => [ "1", 2, "publish", "text_input", 0 ],
      "version" => [ Txp::VERSION, 2, "publish", "text_input", 0 ],
      "default_section" => [ "articles", 2, "section", "text_input", 0 ],
      "thumb_secret" => [ "", 2, "publish", "text_input", 0 ]
    }.freeze

    module_function

    # Creates missing preferences (existing values are kept).
    def install!(overrides = {})
      existing = Pref.global.pluck(:name).to_set
      LIST.each do |name, (val, type, event, html, position)|
        next if existing.include?(name)

        val = overrides.fetch(name, val)
        # As \Textpattern\DB\Core::getPrefsDefault() does at setup.
        val = SecureRandom.hex(16) if name == "blog_uid" && val.to_s.empty?
        val = "#{SecureRandom.hex(16)}blog@example.com" if name == "blog_mail_uid" && val.to_s.empty?
        val = SecureRandom.hex(24) if name == "thumb_secret" && val.to_s.empty?
        Pref.create!(name: name, val: val.to_s, type: type, event: event, html: html, position: position, user_name: "")
      end
    end
  end
end
