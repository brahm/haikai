module Txp
  # Number spelling for escape="spell" / escape="ordinal".
  module Numbers
    module_function

    EN_ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen].freeze
    EN_TENS = %w[_ _ twenty thirty forty fifty sixty seventy eighty ninety].freeze
    PT_ONES = %w[zero um dois três quatro cinco seis sete oito nove dez onze doze treze catorze quinze dezesseis dezessete dezoito dezenove].freeze
    PT_TENS = %w[_ _ vinte trinta quarenta cinquenta sessenta setenta oitenta noventa].freeze
    PT_HUNDREDS = %w[_ cento duzentos trezentos quatrocentos quinhentos seiscentos setecentos oitocentos novecentos].freeze

    def spell(value, lang = "en")
      n = value.to_f
      return value.to_s unless n == n.round && n.abs < 1_000_000_000_000

      n = n.to_i
      words = lang.to_s.start_with?("pt") ? spell_pt(n.abs) : spell_en(n.abs)
      n.negative? ? "#{lang.to_s.start_with?('pt') ? 'menos' : 'minus'} #{words}" : words
    end

    def spell_en(n)
      return EN_ONES[n] if n < 20
      return EN_TENS[n / 10] + (n % 10).nonzero?.then { |r| r ? "-#{EN_ONES[r]}" : "" } if n < 100
      return "#{EN_ONES[n / 100]} hundred#{(n % 100).nonzero? ? " #{spell_en(n % 100)}" : ''}" if n < 1000

      [ [ 1_000_000_000, "billion" ], [ 1_000_000, "million" ], [ 1000, "thousand" ] ].each do |size, name|
        next if n < size

        rest = n % size
        return "#{spell_en(n / size)} #{name}#{rest.nonzero? ? " #{spell_en(rest)}" : ''}"
      end
    end

    def spell_pt(n)
      return PT_ONES[n] if n < 20
      return PT_TENS[n / 10] + ((n % 10).nonzero? ? " e #{PT_ONES[n % 10]}" : "") if n < 100
      return "cem" if n == 100
      return PT_HUNDREDS[n / 100] + ((n % 100).nonzero? ? " e #{spell_pt(n % 100)}" : "") if n < 1000

      [ [ 1_000_000_000, "bilhão", "bilhões" ], [ 1_000_000, "milhão", "milhões" ], [ 1000, "mil", "mil" ] ].each do |size, one, many|
        next if n < size

        count = n / size
        rest = n % size
        head = size == 1000 && count == 1 ? "mil" : "#{spell_pt(count)} #{count == 1 ? one : many}"
        return head + (rest.nonzero? ? "#{rest < 100 || (rest % 100).zero? ? ' e ' : ' '}#{spell_pt(rest)}" : "")
      end
    end

    def ordinal(value, lang = "en")
      n = value.to_i
      if lang.to_s.start_with?("pt", "es", "it")
        "#{n}º"
      elsif lang.to_s.start_with?("fr")
        n == 1 ? "1er" : "#{n}e"
      elsif lang.to_s.start_with?("de")
        "#{n}."
      else
        suffix = (11..13).cover?(n.abs % 100) ? "th" : { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(n.abs % 10, "th")
        "#{n}#{suffix}"
      end
    end
  end
end
