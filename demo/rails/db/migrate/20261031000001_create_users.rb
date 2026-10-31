class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :role, null: false, default: "member"
      t.string :city
      t.string :weather_summary
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
