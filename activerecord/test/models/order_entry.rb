class OrderEntry < ActiveRecord::Base
  belongs_to :order
  validates :title, presence: true
end
