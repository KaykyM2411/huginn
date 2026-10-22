class AddHuginnArrayTestColumns < ActiveRecord::Migration[7.0]
  def change
    add_column :people, :tags, :string, array: true, null: false, default: []
    add_column :people, :tag_ids, :uuid, array: true, default: []
    add_column :companies, :labels, :string, array: true, null: false, default: []
  end
end
