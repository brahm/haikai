module Txp
  # Ruby plugins stored in txp_plugin. A plugin's code runs inside the
  # Txp::Plugins::Context DSL and may register tags, callbacks and privileges:
  #
  #   tag :hello do |txp, atts, thing|
  #     "Hello #{atts['name']}"
  #   end
  #
  #   callback "comment.saved" do |comment:, **|
  #     Rails.logger.info("New comment #{comment.id}")
  #   end
  module Plugins
    module_function

    class Context
      def initialize(plugin_name, registry)
        @plugin = plugin_name
        @registry = registry
      end

      def tag(name, atts: nil, &block)
        @registry.register(name.to_s, atts: atts) { |txp, a, thing, *rest| block.call(txp, a, thing, *rest) }
      end

      def attribute(name, &block)
        @registry.register_attr(block, name.to_s)
      end

      def callback(event, step = "", pre = 0, &block)
        Txp::Callbacks.register(event, step, pre, &block)
      end

      def add_privs(resource, perm = "1")
        Txp::Privs.add(resource, perm)
      end

      def textpack(content)
        Txp::Textpack.import(content, owner: @plugin)
      end

      # Adds an admin-side panel: the block receives the admin controller and
      # returns HTML for the panel body.
      #
      #   admin_tab "extensions", "abc_stats", "Stats" do |admin|
      #     "<h1 class='txp-heading'>Stats</h1><p>#{Article.count} articles</p>"
      #   end
      def admin_tab(area, event, label, privs: "1,2", &block)
        Txp::Plugins.admin_tabs[area.to_s] << [ label.to_s, event.to_s ]
        Txp::Plugins.admin_panels[event.to_s] = block
        Txp::Privs.add(event.to_s, privs)
      end
    end

    def admin_tabs
      @admin_tabs ||= Hash.new { |h, k| h[k] = [] }
    end

    def admin_panels
      @admin_panels ||= {}
    end

    def active
      @active ||= {}
    end

    def errors
      @errors ||= {}
    end

    # Loads all active plugins into the default registry (idempotent per
    # plugin code checksum).
    def load!
      return unless ActiveRecord::Base.connection.data_source_exists?("txp_plugin")

      signature = Plugin.where(status: 1).order(:load_order, :name).pluck(:name, :code_md5, :version)
      return if @signature == signature

      Registry.reset!
      Callbacks.reset!
      @admin_tabs = nil
      @admin_panels = nil
      @active = {}
      @errors = {}
      registry = Registry.default
      Plugin.where(status: 1).order(:load_order, :name).each do |plugin|
        Context.new(plugin.name, registry).instance_eval(plugin.code.to_s, "plugin:#{plugin.name}")
        @active[plugin.name] = { version: plugin.version }
      rescue StandardError, SyntaxError => e
        @errors[plugin.name] = "#{e.class}: #{e.message}"
        Rails.logger.error("[txp] plugin #{plugin.name} failed: #{e.message}")
      end
      @signature = signature
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def reset!
      @signature = nil
    end

    # Parses a plugin package. Supports the Textpattern base64 format
    # (serialized/gzipped PHP array) for metadata and plain Ruby source files
    # with a comment header:
    #
    #   # name: abc_hello
    #   # version: 1.0
    #   # author: Someone
    #   # description: Says hello
    def parse_package(text)
      text = text.to_s.strip
      if text.match?(/\A[A-Za-z0-9+\/=\s]+\z/) && text.length > 40
        decoded = Base64.decode64(text.gsub(/\s+/, ""))
        decoded = Zlib::Inflate.inflate(decoded) rescue decoded
        return parse_php_serialized_plugin(decoded)
      end

      meta = {}
      text.each_line(chomp: true) do |line|
        break unless line.start_with?("#")

        if (m = line.match(/\A#\s*(\w+)\s*:\s*(.+)\z/))
          meta[m[1].downcase] = m[2].strip
        end
      end
      {
        "name" => meta["name"], "version" => meta["version"] || "1.0", "author" => meta["author"].to_s,
        "author_uri" => meta["author_uri"].to_s, "description" => meta["description"].to_s,
        "help" => meta["help"].to_s, "type" => meta["type"].to_i, "load_order" => (meta["order"] || 5).to_i,
        "code" => text
      }
    end

    def parse_php_serialized_plugin(data)
      fields = {}
      data.scan(/s:\d+:"(\w+)";s:(\d+):"/) do |key, _len|
        fields[key] = true
      end
      out = {}
      %w[name version author author_uri description help code type order].each do |key|
        m = data.match(/s:#{key.length}:"#{key}";(?:s:(\d+):"|i:(\d+);)/)
        next unless m

        if m[1]
          start = m.end(0)
          out[key] = data.byteslice(start, m[1].to_i).force_encoding("UTF-8")
        else
          out[key] = m[2].to_i
        end
      end
      out["load_order"] = out.delete("order") || 5
      out["php"] = true
      out
    end
  end
end
