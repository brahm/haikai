module Txp
  # Splits template markup into text and <txp:tag> tokens, the same way
  # Textpattern's txp_tokenize() does. The result for a given string is cached
  # (container contents are cached too, so nested parse() calls are cheap).
  #
  # A parsed string is represented by a Parsed struct:
  #   tags  - [text, tag, text, tag, ..., text]; each tag is
  #           [opening chunk, name, attribute string, inner content|nil, closing chunk|nil]
  #   first - index of the <txp:else /> tag (or one past the last tag)
  #   last  - index of the last tag
  #   test  - evaluation order for tags written as <txp:tag[n] />, or nil
  class Tokenizer
    TAG_NAME = '[\-\w-\u{10FFFF}]+'

    Parsed = Struct.new(:tags, :first, :last, :test)

    Warning = Struct.new(:key, :params)

    attr_reader :short_tags

    def initialize(short_tags: true)
      @short_tags = short_tags
      pattern = short_tags ? "txp|[a-z]+:" : "txp:?"
      @split_re = %r{(</?(?:#{pattern}):#{TAG_NAME}(?:\[-?\d+\])?(?:\s+\$?#{TAG_NAME}(?:\s*=\s*(?:"(?:[^"]|"")*"|'(?:[^']|'')*'|[^\s'"/>]+))?)*\s*/?(?<!--)>)}m
      @tag_re = %r{\A</?(#{pattern}):(#{TAG_NAME})(?:\[(-?\d+)\])?(.*)>\z}m
      @detect_re = /<(?:#{pattern}):/
      @cache = Concurrent::Map.new
    end

    # True if the string contains something that looks like a Textpattern tag.
    def tags?(thing)
      !thing.nil? && @detect_re.match?(thing)
    end

    # Returns a Parsed struct, or nil if the string contains no tags.
    # Warnings about malformed markup are yielded to the optional block.
    def parse(thing, &warn)
      return nil if thing.nil? || !tags?(thing)

      cached = @cache[thing]
      return cached unless cached.nil?

      @cache.clear if @cache.size > 20_000
      tokenize(thing, &warn) || false.tap { @cache[thing] = false }
      result = @cache[thing]
      result == false ? nil : result
    end

    # Splits raw markup into [text, tag chunk, text, ...].
    def split(thing)
      thing.split(@split_re, -1).tap { |a| a << "" if a.empty? }
    end

    private

    def tokenize(thing, &warn)
      parsed = split(thing).map { |s| s.dup.freeze }
      last = parsed.length
      return false if last == 1

      inside = [ parsed[0].dup ]
      tags = [ [ parsed[0] ] ]
      tag = []
      outside = []
      order = [ {} ]
      els = [ -1 ]
      count = [ -1 ]
      level = 0
      i = 1

      while i < last || level > 0
        chunk = i < last ? parsed[i] : "</txp:#{tag[level - 1][2]}>"
        m = @tag_re.match(chunk)
        tag[level] = m ? m.to_a : [ chunk, "txp", "", nil, "" ]
        tag[level][4] = tag[level][4].to_s
        count[level] += 2

        if tag[level][2] == "else"
          els[level] = count[level]
        elsif tag[level][1] == "txp:"
          # <txp::shortcode /> is an alias for <txp:output_form form="shortcode" />
          tag[level][4] = "#{tag[level][4]} form=\"#{tag[level][2]}\""
          tag[level][2] = "output_form"
        elsif @short_tags && tag[level][1] != "txp"
          # <prefix::tag /> is an alias for <txp:prefix_tag />
          tag[level][2] = "#{tag[level][1].chomp(':')}_#{tag[level][2]}"
        end

        if chunk[-2] == "/"
          # Self-closed tag.
          warn&.call(Warning.new("ambiguous_tag_format", "{chunk}" => chunk)) if chunk[1] == "/"
          tags[level] << [ chunk, tag[level][2], tag[level][4].sub(%r{/+\z}, "").strip, nil, nil ]
          inside[level] << chunk
          order[level][tags[level].length / 2] = tag[level][3] if tag[level][3] && tag[level][3] != ""
        elsif chunk[1] != "/"
          # Opening tag.
          inside[level] << chunk
          order[level][(tags[level].length + 1) / 2] = tag[level][3] if tag[level][3] && tag[level][3] != ""
          level += 1
          outside[level] = chunk
          inside[level] = +""
          els[level] = count[level] = -1
          tags[level] = []
          order[level] = {}
        elsif level < 1
          # Closing tag without an opening one.
          warn&.call(Warning.new("missing_open_tag", "{chunk}" => chunk))
          tags[level] << [ chunk, nil, "", nil, nil ]
          inside[level] << chunk
        else
          if i >= last
            warn&.call(Warning.new("missing_close_tag", "{chunk}" => outside[level]))
          elsif tag[level - 1][2] != tag[level][2]
            warn&.call(Warning.new("mismatch_open_close_tag", "{from}" => outside[level], "{to}" => chunk))
          end

          fill(inside[level], tags[level], order[level], count[level], els[level]) if count[level] > 2

          level -= 1
          tags[level] << [ outside[level + 1], tag[level][2], tag[level][4].strip, inside[level + 1], chunk ]
          inside[level] << inside[level + 1] << chunk
        end

        i += 1
        text = i < last ? parsed[i] : ""
        tags[level] << text
        inside[level] << text
        i += 1
      end

      fill(thing, tags[0], order[0], count[0] + 2, els[0])
      true
    end

    def fill(key, tags, order, count, els)
      test = nil

      unless order.empty?
        pre = order.select { |_k, v| v.to_i.positive? }.sort_by { |_k, v| v.to_i }.map(&:first)
        post = order.select { |_k, v| v.to_i.negative? }.sort_by { |_k, v| v.to_i }.map(&:first)
        test = if post.any?
          pre + [ 0 ] + post
        elsif pre.any?
          pre
        end
      end

      @cache[key.frozen? ? key : key.dup.freeze] = Parsed.new(tags.freeze, els.positive? ? els : count, count - 2, test)
    end
  end
end
