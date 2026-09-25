module Admin
  # Inline help (event=help&step=pophelp&item=...), loaded by the pophelp
  # links next to form fields.
  class HelpController < BaseController
    self.event_name = "help"
    self.default_step = :dashboard

    step "pophelp", :pophelp

    private

    def pophelp
      item = params[:item].to_s
      return head(:bad_request) unless Txp::Pophelp.valid_key?(item)

      topic = Txp::Pophelp.topic(item, params[:lang].presence || lang_ui)
      html = if topic
        "#{topic[:html]}\n"
      elsif Txp::Textpack.strings(lang_ui).key?(item.downcase)
        gTxt(item)
      else
        gTxt("pophelp_missing", "{item}" => item)
      end
      out = view_context.content_tag(:div, html.to_s.html_safe, id: "pophelp-event", dir: "auto")

      if request.xhr?
        render html: out
      else
        @page_title = topic ? topic[:title] : gTxt("help")
        render html: out, layout: "admin"
      end
    end

    def dashboard
      @page_title = gTxt("tab_help")
      render html: "", layout: "admin"
    end
  end
end
