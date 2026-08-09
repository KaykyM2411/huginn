# frozen_string_literal: true

module Huginn
  module Searchable
    # Builds an Arel predicate for a single searchable column.
    #
    # Strategy chain (driven by Huginn.configuration.search_strategy):
    #
    #   :pg_trgm   -> trigram similarity (%) OR unaccent+ILIKE (best for typos).
    #                 Both branches are supported by a gin_trgm_ops GIN index
    #                 on UNACCENT(col); the index is used only when it exists.
    #   :unaccent  -> unaccent + ILIKE (case/accents insensitive)
    #   :simple    -> plain LIKE
    module Fuzzy
      # Gentle helpers to wrap a node in UNACCENT(...). The function name comes
      # from Huginn.configuration.unaccent_function so an IMMUTABLE wrapper can
      # be swapped in to make GIN trigram indexes usable.
      module Unaccentable
        private

        def unaccent(node)
          Arel::Nodes::NamedFunction.new(unaccent_function, [node])
        end

        def unaccent_function
          Huginn.configuration.unaccent_function
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

        def initialize(column, value)
          @column = column
          @value = value
        end

        def predicate
          similarity = Arel::Nodes::InfixOperation.new("%", unaccent(@column), unaccent(value))
          similarity.or(fallback)
        end

        private

        def value
          Arel::Nodes.build_quoted(@value, @column)
        end

        def fallback
          Unaccent.new(@column, @value).predicate
        end
      end
    end
  end
end