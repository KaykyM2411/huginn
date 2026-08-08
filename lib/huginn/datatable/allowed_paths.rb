# frozen_string_literal: true

module Huginn
  module Datatable
    # Expands the `allowed_paths:` allowlist into its canonical association
    # chains and answers whether a given chain is authorized.
    #
    # Accepts the same shapes Rails knows: a Symbol, a String, a Hash of
    # nested associations, or an Array mixing those — e.g.
    #
    #   allowed_paths: [:company, { company: :people }, "products"]
    #
    # Every path is canonicalized through the reflection so that table names
    # and public aliases map to the association name the querier actually
    # walks.
    class AllowedPaths
      def self.call(model, spec)
        new(model, spec)
      end

      def initialize(model, spec)
        @model = model
        @allowed = expand(spec)
      end

      def allow(reference_or_spec)
        self.class.call(@model, reference_or_spec)
      end

      # Authorizes an association chain produced by a huginn_attributes alias
      # (canonicalized), even when the raw allowlist does not mention it.
      def include_path(path)
        @allowed << canonicalize_path(path)
      end

      # Canonical association-name path for a Validator/association Path.
      def include?(path)
        return false if path.blank?

        canonical = canonicalize_path(path)
        @allowed.include?(canonical)
      end

      def any?
        @allowed.any?
      end

      def to_a
        @allowed.dup
      end

      private

      attr_reader :model

      def expand(spec)
        paths = case spec
        when nil then []
        when Hash then expand_hash(spec)
        else Array(spec).flat_map { |node| expand_hash(node) }
        end
        paths.map { |path| canonicalize_path(path) }.uniq
      end

      def expand_hash(node, prefix = [])
        case node
        when Symbol, String
          chain = [*prefix, node.to_s]
          [*top_level_paths(chain), chain]
        when Array
          node.flat_map { |child| expand_hash(child, prefix) }
        when Hash
          node.flat_map do |assoc, child|
            current = [*prefix, assoc.to_s]
            [current] + expand_hash(child, current)
          end
        else
          []
        end
      end

      # A bare association in the allowlist also authorizes the "table_name
      # of that association" reference used by scoped columns, e.g. allowing
      # `:company` also allows `companies.name` columns.
      def top_level_paths(chain)
        first = chain.first
        assoc = model.reflect_on_association(first.to_sym)
        return [] unless assoc && chain.size == 1

        [[assoc.klass.table_name]]
      end

      # Normalizes a path of names (association/table/alias) into the
      # canonical list of reflection names the datatable can walk.
      def canonicalize_path(names)
        klass = model
        paths = []

        names.each_with_index do |segment, index|
          reflection = klass.reflect_on_association(segment.to_sym)
          reflection ||= index.zero? ? table_reflection(klass, segment) : nil

          if reflection
            paths << reflection.name.to_s
            klass = reflection.klass
          elsif index.zero? && (table_klass = klass_for_table(segment))
            paths << table_klass.table_name
            klass = table_klass
          else
            paths << segment.to_s
          end
        end

        paths
      end

      def table_reflection(klass, name)
        klass.reflect_on_all_associations.find { |ref| ref.klass == klass_for_table(name) }
      end

      def klass_for_table(name)
        table = name.singularize.camelize.constantize
        table < ActiveRecord::Base ? table : nil
      rescue NameError
        nil
      end
    end
  end
end