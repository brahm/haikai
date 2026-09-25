module Txp
  # Event callbacks (register_callback / callback_event) for plugins.
  module Callbacks
    module_function

    def handlers
      @handlers ||= Hash.new { |h, k| h[k] = [] }
    end

    def register(event, step = "", pre = 0, &block)
      handlers[[ event.to_s, step.to_s, pre.to_i ]] << block
    end

    def fire(event, step = "", pre = 0, **data)
      step, data = "", step if step.is_a?(Hash)
      results = handlers[[ event.to_s, step.to_s, pre.to_i ]].map { |h| h.call(**data) }
      results += handlers[[ event.to_s, "", pre.to_i ]].map { |h| h.call(**data) } if step.to_s != ""
      results.compact.join
    end

    def any?(event, step = "", pre = 0)
      handlers.key?([ event.to_s, step.to_s, pre.to_i ])
    end

    def reset!
      @handlers = nil
    end
  end
end
