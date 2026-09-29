# Liquid filter that abbreviates large counts for stat displays:
#
#   {{ 950 | compact_number }}        => "950"
#   {{ 3966 | compact_number }}       => "3.9K"
#   {{ 125430 | compact_number }}     => "125K"
#   {{ 1250000 | compact_number }}    => "1.2M"
#
# Values are truncated, never rounded up, so a stat is never overstated.
# Non-numeric input (e.g. nil from a failed fetch) passes through unchanged.
module WhittakerTech
  module CompactNumber
    UNITS = [[1_000_000_000, "B"], [1_000_000, "M"], [1_000, "K"]].freeze

    def compact_number(input)
      return input unless input.is_a?(Numeric)

      value = input.to_i
      divisor, suffix = UNITS.find { |unit, _| value.abs >= unit }
      return value.to_s unless divisor

      scaled = value.to_f / divisor
      scaled = scaled.abs < 100 ? (scaled * 10).truncate / 10.0 : scaled.truncate
      "#{scaled.to_s.delete_suffix('.0')}#{suffix}"
    end
  end
end

Liquid::Template.register_filter(WhittakerTech::CompactNumber)
