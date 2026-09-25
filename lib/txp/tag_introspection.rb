module Txp
  # Discovers a tag's attributes and defaults by running its handler in
  # "grok" mode: lAtts() raises with the attribute list (like getAtts()).
  module TagIntrospection
    class Grok < StandardError
      attr_reader :atts

      def initialize(atts)
        super("grok")
        @atts = atts
      end
    end

    module_function

    def attributes(tag, registry: Registry.default)
      entry = registry.tags[tag.to_s]
      return {} unless entry

      r = Renderer.new(registry: registry)
      r.pretext["@txp_grok"] = true
      fake = { "thisid" => 0, "name" => "x", "id" => 0, "title" => "", "type" => "article", "section" => "default" }
      %i[thisarticle thiscomment thisfile thisimage thislink thissection thiscategory].each { |v| r.send(:"#{v}=", fake.dup) }
      atts = entry.atts || {}
      case entry.callable
      when Symbol then r.send(entry.callable, atts, nil, *entry.params)
      when Proc then entry.callable.call(r, atts, nil, *entry.params)
      end
      {}
    rescue Grok => e
      e.atts.reject { |k, _| k.start_with?("$") }
    rescue StandardError
      {}
    end
  end
end
