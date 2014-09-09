require "sinatra"
require "sequel"
require "sequel/extensions/core_extensions" # for lit()
require "json"

DB = Sequel.connect(ARGV.shift || "sqlite://deployments.db")
DB.create_table? :environments do
  String :name, :null => false, :unique => true
  primary_key :id
end

DB.create_table? :deployments do
  String :name, :null => false, :index => true
  String :version, :null => false
  String :hostname
  String :deployed_by
  Time   :deployed_at, :null => false, :default => "datetime('now', 'localtime')".lit

  primary_key :id
  foreign_key :environment_id, :environments, :null => false
end

class Deployment < Sequel::Model
  many_to_one :environment

  dataset_module do
    def latest
      # Add sorting to the Name and Date columns on the homepage. 
#      eager(:environment).order(:environment_id, :name).group_by(:environment_id, :name).having { max(id) }
      eager(:environment).order(:name, :deployed_at, :environment_id).group_by(:environment_id, :name).having { max(id) }
    end
  end
end

class Environment < Sequel::Model
  one_to_many :deployments
end

class DeployManager
  
  class << self
    
    def latest(q = {})
      env = q["env"].to_i
      rs = Deployment.latest
      rs = rs.where(:environment_id => env) if env > 0
      # rs.all

        # 1. For pagination, usually can be archieve by using gem will_paginate.
        # 2. Can use https://github.com/masterkain/classic_pagination, which works only for rails 2
        # @items_pages, @deploys = paginate :items, :order => sort, :conditions => conditions, :per_page => size

      # how many record per page i want to show
      size = pageSize
      
      #params via GET from URL
      page = q["page"].to_i
      page = 1 if page == 0
      rs = rs.limit(size, size*(page-1))
       
    end
    
    def getTotal(q = {})
      env = q["env"].to_i
      rs = Deployment.latest
      rs = rs.where(:environment_id => env) if env > 0
      rs.all.count
    end

    def list(q = {})
       q = q.dup
       page = q.delete(:page).to_i
       page = 1  unless page > 0
       
       size = q.delete(:size).to_i
       size = 10 unless size > 0
     
       # order...
       Deployment.where(q).limit(size * page, page - 1)
     end
    
    def delete(id)
      Deployment.where(:id => id).delete
    end

    def create(attrs)
      attrs = attrs.dup
      Deployment.db.transaction do
        env = Environment.find_or_create(:name => attrs.delete("environment"))
        Deployment.create(attrs.merge(:environment => env))
      end
    end

    def environments
      Environment.all
    end
    
    def pageSize
      2
    end
    
  end
end

helpers do
  def h(text)
    Rack::Utils.escape_html(text)
  end
  
end

post "/deploy/:id/delete" do
  DeployManager.delete(params[:id])
  #redirect to("/")
  200
end

post "/deploy" do
  DeployManager.create(params)
  redirect to("/")
  201
end

# Add a form that allows one to create deployment data.
  # eg: http://localhost:4567/new
get "/new" do
  @environments = DeployManager.environments
  erb :new
end

get "/" do
  @deploys      = DeployManager.latest(params)
  @environments = DeployManager.environments
  # how many record per page i want to show
  @size = DeployManager.pageSize
  @deploymentTotal = DeployManager.getTotal(params);
  erb :index
end
