class Street < ActiveRecord::Base
   attr_accessible :street_name, :ward_name, :municipal_name, :city_name, :lat, :lng, :id
   validates_presence_of :street_name, :ward_name
   has_many :users
end
