class CreatePosts < ActiveRecord::Migration[8.1]
  def change
    create_table :posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body, null: false
      t.datetime :published_at
      t.integer :comments_count, null: false, default: 0
      t.timestamps
    end
    add_index :posts, :slug, unique: true
    add_index :posts, :published_at
  end
end
