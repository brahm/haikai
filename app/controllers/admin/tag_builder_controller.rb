module Admin
  # The Tag builder (event=tag): lists registered tags, discovers their
  # attributes by introspection and builds tag markup.
  class TagBuilderController < BaseController
    self.event_name = "tag"
    self.default_step = :index

    step "build", :index

    private

    def index
      @page_title = gTxt("tagbuilder")
      @tags = Txp::Registry.default.tags.keys.sort
      @tag = @tags.include?(params[:tag_name].to_s) ? params[:tag_name].to_s : nil
      if @tag
        @attributes = Txp::TagIntrospection.attributes(@tag)
        values = params.fetch(:atts, {}).to_unsafe_h.reject { |_k, v| v.to_s.empty? }
        @values = values
        @result = build_tag(@tag, values, params[:content].to_s)
      end
      render "admin/tag_builder/index"
    end

    def build_tag(tag, atts, content)
      attr = atts.map { |k, v| v == "1" && @attributes[k] == true ? " #{k}" : %( #{k}="#{v.to_s.gsub('"', '""')}") }.join
      content.present? ? "<txp:#{tag}#{attr}>#{content}</txp:#{tag}>" : "<txp:#{tag}#{attr} />"
    end
  end
end
