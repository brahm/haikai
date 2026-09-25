module Txp
  # Tag and global attribute registry (port of \Textpattern\Tag\Registry).
  #
  # Tags map to renderer methods (Symbols) or to Procs receiving the renderer
  # as the first argument, which is how Ruby plugins add new tags:
  #
  #   Txp::Registry.default.register("hello") do |txp, atts, thing|
  #     "Hello #{txp.php_str(atts['name'])}"
  #   end
  class Registry
    Entry = Struct.new(:callable, :atts, :params)

    attr_reader :tags, :attrs

    def self.default
      @default ||= new.tap(&:load_core!)
    end

    def self.reset!
      @default = nil
    end

    def initialize
      @tags = {}
      @attrs = {}
    end

    def register(name, callable = nil, atts: nil, params: [], &block)
      callable ||= block || :"tag_#{name}"
      @tags[name.to_s] = Entry.new(callable, atts&.transform_keys(&:to_s), Array(params))
      self
    end

    # handler: true (known attribute, handled by tags themselves), a Symbol
    # (renderer method) or a Proc.
    def register_attr(handler, names)
      Php.do_list_unique(names).each { |n| @attrs[n] = handler }
      self
    end

    def registered?(name)
      @tags.key?(name.to_s)
    end

    def registered_attr?(name)
      h = @attrs[name.to_s]
      !h.nil? && h != true && h != false
    end

    def global_atts
      @attrs
    end

    def unregister(name)
      @tags.delete(name.to_s)
    end

    # Returns the tag output as a String, or false for unknown tags.
    def process(renderer, name, atts, thing)
      entry = @tags[name]
      return false if entry.nil?

      if entry.atts
        defaults_globals = entry.atts.select { |k, _| @attrs.key?(k) }
        renderer.txp_atts = defaults_globals.merge(renderer.txp_atts || {}) unless defaults_globals.empty?
        atts = entry.atts.merge(atts)
      end

      result = case entry.callable
      when Symbol then renderer.send(entry.callable, atts, thing, *entry.params)
      when Proc then entry.callable.call(renderer, atts, thing, *entry.params)
      end

      Php.str(result)
    rescue Txp::Die, Txp::Redirect
      raise
    rescue StandardError => e
      renderer.tag_exception(e)
      ""
    end

    def process_attr(renderer, name, atts, thing)
      handler = @attrs[name]
      case handler
      when Symbol then Php.str(renderer.send(handler, atts, thing))
      when Proc then Php.str(handler.call(renderer, atts, thing))
      else thing
      end
    end

    def load_core!
      register_attr(true, "labeltag, class, html_id, not, breakclass, breakform, wrapform, evaluate")
      register_attr(:txp_escape_attr, "escape")
      register_attr(:txp_deprecate, "$deprecate")
      register_attr(:txp_wraptag, "wraptag, break, breakby, label, trim, replace, default, limit, offset, sort")
      register_attr(:txp_variable_attr, "variable")
      Tags.register_all(self)
      self
    end
  end
end
