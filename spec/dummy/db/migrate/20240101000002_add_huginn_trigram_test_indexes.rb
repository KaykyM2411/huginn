class AddHuginnTrigramTestIndexes < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.f_unaccent(text)
      RETURNS text AS $$
        SELECT public.unaccent('public.unaccent', $1);
      $$
      LANGUAGE sql IMMUTABLE PARALLEL SAFE;
    SQL
    add_index :people, "public.f_unaccent(name) gin_trgm_ops", using: :gin, name: "index_people_name_trgm"

    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.f_tsvector(text)
      RETURNS tsvector AS $$
        SELECT to_tsvector('portuguese', $1);
      $$
      LANGUAGE sql IMMUTABLE PARALLEL SAFE;
    SQL
    add_index :people, "public.f_tsvector(name)", using: :gin, name: "index_people_name_fts"
  end

  def down
    remove_index :people, name: "index_people_name_trgm"
    remove_index :people, name: "index_people_name_fts"
    execute "DROP FUNCTION IF EXISTS public.f_unaccent(text)"
    execute "DROP FUNCTION IF EXISTS public.f_tsvector(text)"
  end
end
