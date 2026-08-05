# frozen_string_literal: true

module Huginn
  module Datatable
    # Normalizes the heterogeneous filter payloads sent by frontends
    # (ActionController::Parameters, Hash, Array of hashes, [key, value]
    # pairs, ...) into a single Hash of { column => Array(values) }.
    #
    # Values are accumulated in arrays so that repeated keys produce an
    # IN condition when applied as a datatable filter. Invalid payload
    # shapes are simply ignored, and keys are normalized to strings.
    class FilterNormalizer
      def self.call(raw)
        new(raw).call
      end

      def initialize(raw)
        @raw = raw
      end

      def call
        each_pair(@raw).each_with_object({}) do |(key, value), acc|
          (acc[key.to_s] ||= []) << value
        end
      end

      private

      def each_pair(raw, &block)
        return enum_for(:each_pair, raw) unless block

        case raw
        when ActionController::Parameters
          raw.to_unsafe_h.each { |key, value| block.call(key, value) }
        when Hash
          raw.each { |key, value| block.call(key, value) }
        when Array
          if pair?(raw)
            block.call(raw.first, raw.last)
          else
            raw.each { |item| each_pair(item) { |key, value| block.call(key, value) } }
          end
        end
      end

      # A two-element array whose first element is a key (String/Symbol)
      # is treated as a single [key, value] pair rather than a list.
      def pair?(array)
        array.size == 2 && (array.first.is_a?(String) || array.first.is_a?(Symbol))
      end
    end
  end
end