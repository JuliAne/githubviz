#!/usr/bin/env ruby

require 'rubygems'
require 'sinatra'
require 'active_record'

class Request < ActiveRecord::Base
end

class ApiConnection

  require 'github_v3_api/github_v3_api.rb'

  def initialize api_key
    puts "#{Time.now}: Initializing ApiConnection..."
    @connection = GitHubV3API.new(api_key)
  end

  def get url, paging=false
    name = url.match(/^\/users\/([^\/]+)\/*/)[1]
    type = url[/[^\/]+$/]
    type = "user" unless %w[repos followers].include? type

    req = Request.where("name = ? AND content_type = ? AND updated_at  > ?", name, type, Time.now - 1.day).limit(1)[0]
    req_check_date = Request.where("name = ? AND content_type = ? AND updated_at <= ?", name, type, Time.now - 1.day).limit(1)[0]
    
    result = []

    if req
      result = JSON.parse(req.content)
    else
      puts "doing an api request..."
      if paging
        (paging / 30.0).ceil.times do |page|
          result += @connection.get "#{url}?page=#{page+1}"
        end
      else
        puts "connection..."
        result = @connection.get url
      end
     
      if req_check_date
        puts "updating db entry..."
        Request.update(req_check_date[:id], :name => name, :content_type => type, :content => result.to_json)
      else
        puts "creating db entry..."
        Request.create!(:name => name, :content_type => type, :content => result.to_json)
      end
    end
    
    result
  end
  
  NoApiKeyError = Class.new(StandardError)
end

class GithubViz < Sinatra::Base

set :app_file, __FILE__

require 'config'

begin
  @@api = ApiConnection.new ENV['GITHUB_API_KEY']
rescue ArgumentError
  raise ApiConnection::NoApiKeyError, "Please set the ENV['GITHUB_API_KEY'] var"
end

ActiveRecord::Base.establish_connection(@@config)
ActiveRecord::Base.connection

def process_circle_data
   @test = {}
   @test['data'] = {}
   @circle_result = @data.keys
   @data.each do |k,v|
    @test['data'][@circle_result.index(k)]= []
    v['followers'].each do |f|
      @test['data'][@circle_result.index(k)]<<  f['login']
    end
   end
   @circle_result.map! {|n|{"name" => n, "imports" => @test['data'][@circle_result.index(n)]}}
end

def aquire_data
   @data[@user] = @@api.get("/users/#{@user}")
end

def filter_data
  @data[@user]['user'] = @@api.get("/users/#{@user}")
  @data[@user]['level'] = 0
  @data[@user]['follower_count'] = @data[@user]['followers']
  @data[@user]['followers'] = @@api.get("/users/#{@user}/followers", @data[@user]['follower_count'])
end

def get_data
  if @level < @MAX_LEVELS
    t = {}
    @data.each do |k,v|
      if v['level'] == @level
        @@api.get("/users/#{k}/followers", v['follower_count']).each do |f|
          unless @data.has_key? f['login']
            t[f['login']] = f
            t[f['login']]['user'] = @@api.get("/users/#{f['login']}")
            t[f['login']]['level'] = @level+1
            t[f['login']]['follower_count'] = t[f['login']]['user']['followers']       
            t[f['login']]['followers'] = @@api.get("/users/#{f['login']}/followers", t[f['login']]['follower_count'])
          end
        end
      end
    end
    @data.merge! t
    @level += 1
    get_data
  end
end

def process_data
  @result['nodes'] = @data.keys
  @result['links'] = []

  @data.each do |k,v|
    v['followers'].each do |f|
      @result['links'] << {
        "source" => @result['nodes'].index(k),
        "target" => @result['nodes'].index(f['login']),
        "value" => 1
      } if @result['nodes'].index(f['login'])
    end
  end

  @result['nodes'].map!{|n| {
    "name" => n,
    "group" => 1,
    "img" => @data[n]['avatar_url'],
    "profilseite" => @data[n]['user']['html_url'],
    "follower_count" => @data[n]['follower_count'],
    "color" => "",
    "public_repos" => @data[n]['user']['public_repos']
  }}

  script_language

end

def script_language
  @scriptlanguage_legend = []
  
  @result['nodes'].each do |user|
    @repos = @@api.get("/users/#{user['name']}/repos", user['public_repos'])
    languages = {}
    
    if @repos.count == 0
      user['scriptlanguage'] = 'nothing'
    else
      @repos.each do |repo|
        
        repo['language'] = 'unknown' if repo['language'].nil?
        
        if languages.has_key? repo['language']
          languages[repo['language']] += 1
        else
          languages[repo['language']] = 1
        end
        
      end

      most_used_languages = {}
      languages.each do |lang_name, lang_count|
        if most_used_languages.has_key? lang_count
          most_used_languages[lang_count] << lang_name
        else
          most_used_languages[lang_count] = [lang_name]
        end
      end
      #{12 => ["Ruby", "C++"], 5 => ["Javascript"], 3 => ['HTML', 'CSS']}

      user['scriptlanguage'] = most_used_languages.sort {|a,b| b[0] <=> a[0]}[0][1]
      #['C++', 'Ruby']
    end
    #prepring to get legend for scriptlanguages
    @scriptlanguage_legend << {"lang" => user['scriptlanguage'], "count" => 0, "color" => ""}
  end

  @legend = @scriptlanguage_legend.uniq
  
  #get languages, count them and add color to result
  @legend.each do |lang|
    colour = "%06x" % (rand * 0xffffff)
    lang["color"] = colour.insert(0, '#')
    @result['nodes'].each do |lang2|
      if lang["lang"] == lang2["scriptlanguage"]
        lang["count"] += 1
        lang2["color"] = lang["color"]
      end
    end
  end
  
  #language sort descending by counts
  @legend = @legend.sort_by {|k| -k['count'] }
end

def represent
  erb :follower
end

get '/' do
  erb :index
end

get '/follower_viz' do

  @level = 0

  @data = {}

  @result = {"1" => "1"}

  @MAX_LEVELS = params[:level].to_i

  @user = params[:user]

  @user_repos = Array.new

  if @user
    aquire_data
    filter_data
    get_data
    process_data
    represent
  end
end

get '/repo_viz' do
  @user = params[:user]

  user_data = @@api.get("/users/#{@user}")

  erb :repo
end

get '/commit_viz' do
  @user = params[:user]
  erb :commit
end

get '/circle_viz' do
  @level = 0
  @circle_result = {}
  @data = {}
  @user = params[:user]
  @MAX_LEVELS = 1
if @user
    @data[@user] = @@api.get("/users/#{@user}")
    @data[@user]['level'] = 0
    @data[@user]['follower_count'] = @data[@user]['followers']
    @data[@user]['followers'] = @@api.get("/users/#{@user}/followers")
    @data[@user]['user'] = @@api.get("/users/#{@user}")
    get_data
    process_circle_data
    end
  erb :circle
end

end
