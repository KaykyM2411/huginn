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
    #   :full_text -> PostgreSQL full text search: to_tsvector(col) @@
    #                 plainto_tsquery(term), so morphological variants match;
    #                 needs the IMMUTABLE fts_function wrapper and a GIN
    #                 tsvector index. Effective with a single strategy or
    #                 combined with :pg_trgm (OR).
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

      # PostgreSQL full text search over lexemes:
      #
      #   public.f_tsvector(col) @@ plainto_tsquery('portuguese'::regconfig, term)
      #
      # The column side runs through the configured fts_function (an IMMUTABLE
      # wrapper around to_tsvector that pins the dictionary, created by
      # `rails g huginn:fts_indexes`) so a GIN tsvector index is usable. The
      # query side uses plainto_tsquery, which ANDs the lexemes of the term and
      # applies stemming — tolerant to morphological variants, blind to typos.
      class FullText
        def initialize(column, value, dictionary: nil)
          @column = column
          @value = value.to_s
          @dictionary = dictionary || Huginn.configuration.fts_dictionary
        end

        def predicate
          Arel::Nodes::InfixOperation.new("@@", tsvector, query)
        end

        private

        def tsvector
          Arel::Nodes::NamedFunction.new(Huginn.configuration.fts_function, [@column])
        end

        def query
          Arel::Nodes::NamedFunction.new("plainto_tsquery", [regconfig, quoted_value])
        end

        def regconfig
          Arel.sql("'#{@dictionary}'::regconfig")
        end

        def quoted_value
          Arel::Nodes.build_quoted(@value, @column)
        end
      end
    end
  end
end
