# frozen_string_literal: true

module Huginn
  module Searchable
    # Builds an Arel predicate for a single searchable column.
    #
    # Strategy chain (driven by Huginn.configuration.search_strategy):
    #
    #   :pg_trgm   -> trigram similarity OR unaccent+ILIKE (best for typos)
    #   :unaccent  -> unaccent + ILIKE (case/accents insensitive)
    #   :simple    -> plain LIKE
    module Fuzzy
      # Gentle helpers to wrap a node in UNACCENT(...).
      module Unaccentable
        private

        def unaccent(node)
          Arel::Nodes::NamedFunction.new("UNACCENT", [node])
        end
      end

      class Simple
        def initialize(column, value)
          @column = column
          @value = value
        end

        def predicate
          @column.matches("%#{escape_like(@value)}%")
        end

        private

        def escape_like(value)
          value.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
        end
      end

      class Unaccent
        include Unaccentable

        def initialize(column, value)
          @column = column
          @value = value
        end

        def predicate
          Arel::Nodes::InfixOperation.new(
            "ILIKE",
            unaccent(@column),
            unaccent(Arel::Nodes.build_quoted("%#{escape_like(@value)}%", @column))
          )
        end

        private

        def escape_like(value)
          value.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
        end
      end

      class Trigram
        include Unaccentable

        def initialize(column, value, threshold)
          @column = column
          @value = value
          @threshold = threshold
        end

        def predicate
          similarity = Arel::Nodes::NamedFunction.new("similarity", [
            unaccent(@column),
            unaccent(Arel::Nodes.build_quoted(@value, @column))
          ])
          threshold = Arel::Nodes.build_quoted(@threshold)
          Arel::Nodes::InfixOperation.new(">", similarity, threshold).or(fallback)
        end

        private

        def fallback
          Unaccent.new(@column, @value).predicate
        end
      end
    end
  end
end