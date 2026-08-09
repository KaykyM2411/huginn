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
  end

  def down
    remove_index :people, name: "index_people_name_trgm"
    execute "DROP FUNCTION IF EXISTS public.f_unaccent(text)"
  end
end