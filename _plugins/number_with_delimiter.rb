# Liquid filter that groups the digits of a count for exact stat displays:
#
#   {{ 3966 | number_with_delimiter }}     => "3,966"
#   {{ 1250000 | number_with_delimiter }}  => "1,250,000"
#
# Non-numeric input (e.g. nil from a failed fetch) passes through unchanged.
module WhittakerTech
  module NumberWithDelimiter
    def number_with_delimiter(input)
      return input unless input.is_a?(Numeric)

      input.to_i.to_s.reverse.scan(/\d{1,3}/).join(",").reverse.then { |digits| input.negative? ? "-#{digits}" : digits }
    end
  end
end

Liquid::Template.register_filter(WhittakerTech::NumberWithDelimiter)
