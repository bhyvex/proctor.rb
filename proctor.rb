require "./environment"

require "sinatra"
require "sinatra/activerecord"
require "oj"

configure do
  set :database, ENV["PROCTOR_DATABASE_URL"]

  set :auth do |*roles|
    condition do
      halt 403 unless roles.any? { |role| current_user.in_role?(role) }
    end
  end

  set :ability do |*things|
    condition do
      things.each do |thing|
        thing = instance_variable_get(thing)
        halt 403 unless ability.can_use?(thing)
      end

      true
    end
  end
end

require "models"
require "ability"

helpers do

  # Public: Return a JSON response by setting up the correct Content-Type
  # header and transforming the given argument to a JSON String.
  #
  # payload - Hash or Array to convert. They keys of any Hash MUST be Strings.
  #
  # Returns a valid JSON String.
  def json(payload)
    content_type :json
    Oj.dump(payload)
  end

  # Public: Return the request body parsed from JSON.
  #
  # Returns Hash, Array or String, depends on the content
  # of the body of the request.
  def parse_body
    request.body.rewind
    Oj.load request.body.read
  end

  def location(url)
    headers "Location" => url
  end

  def current_user
    @current_user ||= User.find_or_initialize_by(:name => env["REMOTE_USER"])
    if @current_user.new_record?
      @current_user.role = "admin"
    end

    @current_user
  end

  def ability
    @ability ||= Ability.new(current_user)
  end
end

def users_path
  "/users"
end

def user_path(name = ":name")
  join_paths users_path, name
end

def user_pubkeys_path(user = ":name")
  join_paths user_path(user), "pubkeys"
end

def user_pubkey_path(user = ":name", title = ":title")
  join_paths user_pubkeys_path(user), title
end

def user_teams_path(user = ":name")
  join_paths user_path(user), "teams"
end

def memberships_path
  "/memberships"
end

def teams_path
  "/teams"
end

def team_path(name = ":name")
  join_paths teams_path, name
end

def team_users_path(name = ":name")
  join_paths team_path(name), "users"
end

def team_pubkeys_path(name = ":name")
  join_paths team_path(name), "pubkeys"
end

def join_paths(*paths)
  paths.join("/")
end

use Rack::Auth::Basic do |username, password|
  user = User.find_by(:name => username)
  # Use default ENV for main admin user
  user ||= User.new(
    :name     => ENV["PROCTOR_ADMIN_USERNAME"],
    :password => ENV["PROCTOR_ADMIN_PASSWORD"],
    :role     => "admin"
  )
  user && user.authenticate(password)
end

before user_path(":name*") do
  @user = User.find_by(:name => params["name"])
  halt 404 if @user.nil?
end

before user_pubkey_path(":name", ":title*") do
  @pubkey = @user.pubkeys.find_by(:title => params["title"])
  halt 404 if @pubkey.nil?
end

before team_path(":name*") do
  @team = Team.find_by(:name => params["name"])
  halt 404 if @team.nil?
end

get "/" do
  "Hello world!"
end

get users_path do
  json User.order(:name).map(&:as_api)
end

get user_path do
  json @user.as_api
end

post users_path, :auth => :admin do
  user = User.new
  user.from_api(parse_body)

  if user.save
    status 201
    location to(user_path(user.name))

    json user.as_api
  else
    status 422 # TODO: check correct error value

    json({ "errors" => user.errors.full_messages })
  end
end

patch user_path, :auth => %i(admin user), :ability => :@user do
  @user.from_api(parse_body)

  if @user.save
    location to(user_path(@user.name))

    json @user.as_api
  else
    status 422 # TODO: check correct error value

    json({ "errors" => @user.errors.full_messages })
  end
end

delete user_path, :auth => %i(admin user), :ability => :@user do
  @user.destroy

  status 204
end

get user_pubkeys_path do
  json @user.pubkeys.order(:title).map(&:as_api)
end

get user_pubkey_path do
  json @pubkey.as_api
end

post user_pubkeys_path, :auth => %i(admin user), :ability => :@user do
  pubkey = @user.pubkeys.new
  pubkey.from_api(parse_body)

  if pubkey.save
    status 201
    location to(user_pubkey_path(@user.name, pubkey.title))

    json pubkey.as_api
  else
    status 422 # TODO: check correct error value

    json({ "errors" => pubkey.errors.full_messages })
  end
end

patch user_pubkey_path, :auth => %i(admin user), :ability => :@pubkey do
  @pubkey.from_api(parse_body)

  if @pubkey.save
    location to(user_pubkey_path(@user.name, @pubkey.title))

    json @pubkey.as_api
  else
    status 422 # TODO: check correct error value

    json({ "errors" => @pubkey.errors.full_messages })
  end
end

delete user_pubkey_path, :auth => %i(admin user), :ability => :@pubkey do
  @pubkey.destroy

  status 204
end

get user_teams_path do
  json @user.teams.map { |team| team.as_json(only: :name) }
end

get teams_path do
  json Team.all.map(&:as_api)
end

get team_path do
  json @team.as_api
end

patch team_path, :auth => :admin do
  @team.attributes = parse_body

  if @team.save
    location to(team_path(@team.name))

    json @team.as_api
  else
    status 422 # TODO: check correct error value

    json({ "errors" => @team.errors.full_messages })
  end
end

delete team_path, :auth => :admin do
  @team.destroy

  status 204
end

get team_users_path do
  json @team.users.map(&:as_api)
end

get team_pubkeys_path do
  json @team.pubkeys.map(&:as_api)
end

post memberships_path, :auth => :admin do
  membership = Membership.link(parse_body)

  if membership.valid?
    status 201
    location to(team_path(membership.team.name))
  else
    status 422 # TODO: check correct error value

    json({ "errors" => membership.errors.full_messages })
  end
end

delete memberships_path, :auth => :admin do
  Membership.unlink(parse_body)

  status 204
end
