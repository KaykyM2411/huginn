class Company < ApplicationRecord
  has_many :people
  has_many :products
end