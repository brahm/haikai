module Txp
  # Tag library. Each module defines tag_<name> handler methods which are
  # mixed into Txp::Renderer; the registration table below maps tag names to
  # handlers, default attributes and extra parameters (like Textpattern's
  # taghandlers.php registry calls).
  module Tags
    def self.modules
      [ Core, Articles, Taxonomy, Comments, Images, Files, Links, Privacy, Pagination ]
    end

    TABLE = [
      # name, handler, default atts, params
      [ "page_title" ], [ "page_url" ], [ "css" ], [ "date", :tag_date ], [ "output_form" ],
      [ "yield" ], [ "if_yield" ], [ "feed_link" ], [ "link_feed_link" ],
      [ "linklist" ], [ "link" ], [ "linkdesctitle" ], [ "link_name" ], [ "link_url" ], [ "link_author" ],
      [ "link_description" ], [ "link_category" ], [ "link_id" ],
      [ "link_date", :tag_date, { "type" => "link", "time" => "date" } ],
      [ "if_first_link", :tag_if_first, nil, [ "link" ] ], [ "if_last_link", :tag_if_last, nil, [ "link" ] ],
      [ "email" ], [ "recent_articles" ], [ "recent_comments" ], [ "related_articles" ], [ "popup" ],
      [ "category_list" ], [ "section_list" ], [ "search_input" ], [ "search_term" ],
      [ "link_to_next", :tag_link_to, nil, [ "next" ] ], [ "link_to_prev", :tag_link_to, nil, [ "prev" ] ],
      [ "next_title" ], [ "prev_title" ], [ "site_name" ], [ "site_slogan" ], [ "link_to_home" ],
      [ "newer", :tag_pager, nil, [ true ] ], [ "older", :tag_pager, nil, [ false ] ], [ "pages", :tag_pager, nil, [ nil ] ],
      [ "text" ], [ "article_id" ], [ "article_url_title" ], [ "if_article_id" ], [ "if_article_status" ],
      [ "posted", :tag_date, { "type" => "article", "time" => "posted" } ],
      [ "modified", :tag_date, { "type" => "article", "time" => "modified" } ],
      [ "expires", :tag_date, { "type" => "article", "time" => "expires" } ],
      [ "if_expires" ], [ "if_expired" ], [ "comments_invite" ], [ "comments_count" ], [ "comments_help" ],
      [ "comment_name_input", :tag_comment_input, nil, [ "name", false ] ],
      [ "comment_email_input", :tag_comment_input, nil, [ "email", true ] ],
      [ "comment_web_input", :tag_comment_input, { "placeholder" => "http(s)://" }, [ "web", true ] ],
      [ "comment_message_input" ], [ "comment_remember" ], [ "comment_preview" ], [ "comment_submit" ],
      [ "comments_form" ], [ "comments_error" ], [ "comments" ], [ "comments_preview" ], [ "comment_permlink" ],
      [ "comment_id" ], [ "comment_name" ], [ "comment_email" ], [ "comment_web" ], [ "comment_message" ],
      # Textpattern 4.9 registers comments_help to a method that does not exist
      # and never registers popup_comments; both work here.
      [ "comment_anchor" ], [ "popup_comments" ],
      [ "comment_time", :tag_date, { "type" => "comment", "time" => "time" } ],
      [ "authors" ], [ "author" ], [ "author_email" ], [ "if_author" ], [ "if_article_author" ],
      [ "body" ], [ "title" ], [ "excerpt" ],
      [ "category1", :tag_article_category ], [ "category2", :tag_article_category, { "number" => 2 } ],
      [ "category" ], [ "section" ], [ "keywords" ], [ "if_keywords" ], [ "if_description" ],
      [ "if_article_image" ], [ "article_image" ],
      [ "image" ], [ "image_index" ], [ "image_display" ], [ "images" ], [ "image_info" ], [ "image_url" ],
      [ "image_author" ], [ "image_date" ], [ "if_thumbnail" ], [ "thumbnail" ],
      [ "if_first_image", :tag_if_first, nil, [ "image" ] ], [ "if_last_image", :tag_if_last, nil, [ "image" ] ],
      [ "search_result_title" ], [ "search_result_excerpt" ], [ "search_result_url" ],
      [ "search_result_date", :tag_date, { "type" => "article", "time" => "posted", "$deprecate" => true } ],
      [ "search_result_count", :tag_items_count, { "$deprecate" => true } ],
      [ "items_count" ], [ "if_items_count" ], [ "if_search_results", :tag_if_items_count ], [ "if_search" ],
      [ "if_comments" ], [ "if_comments_preview" ], [ "if_comments_error" ], [ "if_comments_allowed" ],
      [ "if_comments_disallowed" ], [ "if_individual_article" ], [ "if_article_list" ],
      [ "meta_keywords" ], [ "meta_description" ], [ "meta_author" ], [ "permlink" ], [ "lang" ], [ "breadcrumb" ],
      [ "if_excerpt" ], [ "if_category" ], [ "if_article_category" ],
      [ "if_first_category", :tag_if_first, nil, [ "category" ] ], [ "if_last_category", :tag_if_last, nil, [ "category" ] ],
      [ "if_section" ], [ "if_article_section" ],
      [ "if_first_section", :tag_if_first, nil, [ "section" ] ], [ "if_last_section", :tag_if_last, nil, [ "section" ] ],
      [ "if_logged_in" ], [ "password_protect" ], [ "if_request" ], [ "hide" ], [ "php" ], [ "header" ],
      [ "custom_field" ], [ "if_custom_field" ], [ "site_url" ], [ "error_message" ], [ "error_status" ],
      [ "if_status" ], [ "if_different" ],
      [ "if_first_article", :tag_if_first, nil, [ "article" ] ], [ "if_last_article", :tag_if_last, nil, [ "article" ] ],
      [ "if_plugin" ],
      [ "file_download_list" ], [ "file_download" ], [ "file_download_info" ], [ "file_download_link" ],
      [ "file_download_size" ], [ "file_download_id" ], [ "file_download_name" ], [ "file_download_category" ],
      [ "file_download_author" ], [ "file_download_downloads" ], [ "file_download_description" ],
      [ "file_download_created", :tag_date, { "type" => "file", "time" => "created" } ],
      [ "file_download_modified", :tag_date, { "type" => "file", "time" => "modified" } ],
      [ "if_first_file", :tag_if_first, nil, [ "file" ] ], [ "if_last_file", :tag_if_last, nil, [ "file" ] ],
      [ "rsd" ], [ "variable" ], [ "if_variable" ], [ "article" ], [ "article_custom" ],
      [ "txp_die" ], [ "die", :tag_txp_die ], [ "evaluate" ]
    ].freeze

    # txp_sandbox() is registered under an unguessable name, so templates
    # cannot call it directly (Textpattern uses "sandbox_" . uniqid()).
    SANDBOX_TAG = "sandbox_#{SecureRandom.hex(8)}".freeze

    def self.register_all(registry)
      TABLE.each do |name, handler, atts, params|
        registry.register(name, handler || :"tag_#{name}", atts: atts, params: params || [])
      end
      registry.register(SANDBOX_TAG, :tag_txp_sandbox)
    end
  end
end
