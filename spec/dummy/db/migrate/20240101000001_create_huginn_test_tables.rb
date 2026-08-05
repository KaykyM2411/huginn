class CreateHuginnTestTables < ActiveRecord::Migration[7.0]
  def change
    enable_extension "pg_trgm"
    enable_extension "unaccent"

    create_table :companies do |t|
      t.string :name
      t.string :cnpj
      t.boolean :active, default: true
      t.timestamps
    end

    create_table :people do |t|
      t.references :company, foreign_key: true
      t.string :name
      t.string :email
      t.integer :age
      t.timestamps
    end

    create_table :products do |t|
      t.references :company, foreign_key: true
      t.string :title
      t.string :sku
      t.timestamps
    end
  end
end