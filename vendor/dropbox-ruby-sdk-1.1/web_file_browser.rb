# -------------------------------------------------------------------
# An example webapp that lets you browse and upload files to Dropbox.
# Demonstrates:
# - The webapp OAuth process.
# - The metadata() and put_file() calls.
#
# To run:
# 1. Install Sinatra  $ gem install sinatra
# 2. Launch server    $ ruby web_file_browser.rb
# 3. Browse to        http://localhost:4567/
# -------------------------------------------------------------------

require 'rubygems'
require 'sinatra'
require 'pp'
require './lib/dropbox_sdk'

# Get your app's key and secret from https://www.dropbox.com/developers/
APP_KEY = ''
APP_SECRET = ''
ACCESS_TYPE = :app_folder #The two valid values here are :app_folder and :dropbox
                          #The default is :app_folder, but your application might be
                          #set to have full :dropbox access.  Check your app at
                          #https://www.dropbox.com/developers/apps

# -------------------------------------------------------------------
# OAuth stuff

get '/oauth-start' do
    # OAuth Step 1: Get a request token from Dropbox.
    db_session = DropboxSession.new(APP_KEY, APP_SECRET)
    begin
        db_session.get_request_token
    rescue DropboxError => e
        return html_page "Exception in OAuth step 1", "<p>#{h e}</p>"
    end

    session[:request_db_session] = db_session.serialize

    # OAuth Step 2: Send the user to the Dropbox website so they can authorize
    # our app.  After the user authorizes our app, Dropbox will redirect them
    # to our '/oauth-callback' endpoint.
    auth_url = db_session.get_authorize_url url('/oauth-callback')
    redirect auth_url 
end

get '/oauth-callback' do
    # Finish OAuth Step 2
    ser = session[:request_db_session]
    unless ser
        return html_page "Error in OAuth step 2", "<p>Couldn't find OAuth state in session.</p>"
    end
    db_session = DropboxSession.deserialize(ser)

    # OAuth Step 3: Get an access token from Dropbox.
    begin
        db_session.get_access_token
    rescue DropboxError => e
        return html_page "Exception in OAuth step 3", "<p>#{h e}</p>"
    end
    session.delete(:request_db_session)
    session[:authorized_db_session] = db_session.serialize
    redirect url('/')
    # In this simple example, we store the authorized DropboxSession in the web
    # session hash.  A "real" webapp might store it somewhere more persistent.
end

# If we already have an authorized DropboxSession, returns a DropboxClient.
def get_db_client
    if session[:authorized_db_session]
        db_session = DropboxSession.deserialize(session[:authorized_db_session])
        begin
            return DropboxClient.new(db_session, ACCESS_TYPE)
        rescue DropboxAuthError => e
            # The stored session didn't work.  Fall through and start OAuth.
            session[:authorized_db_session].delete
        end
    end
end

# -------------------------------------------------------------------
# File/folder display stuff

get '/' do
    # Get the DropboxClient object.  Redirect to OAuth flow if necessary.
    db_client = get_db_client
    unless db_client
        redirect url("/oauth-start")
    end

    # Call DropboxClient.metadata
    path = params[:path] || '/'
    begin
        entry = db_client.metadata(path)
    rescue DropboxAuthError => e
        session.delete(:authorized_db_session)  # An auth error means the db_session is probably bad
        return html_page "Dropbox auth error", "<p>#{h e}</p>"
    rescue DropboxError => e
        if e.http_response.code == '404'
            return html_page "Path not found: #{h path}", ""
        else
            return html_page "Dropbox API error", "<pre>#{h e.http_response}</pre>"
        end
    end

    if entry['is_dir']
        render_folder(db_client, entry)
    else
        render_file(db_client, entry)
    end
end

def render_folder(db_client, entry)
    # Provide an upload form (so the user can add files to this folder)
    out = "<form action='/upload' method='post' enctype='multipart/form-data'>"
    out += "<label for='file'>Upload file:</label> <input name='file' type='file'/>"
    out += "<input type='submit' value='Upload'/>"
    out += "<input name='folder' type='hidden' value='#{h entry['path']}'/>"
    out += "</form>"  # TODO: Add a token to counter CSRF attacks.
    # List of folder contents
    entry['contents'].each do |child|
        cp = child['path']      # child path
        cn = File.basename(cp)  # child name
        if (child['is_dir']) then cn += '/' end
        out += "<div><a style='text-decoration: none' href='/?path=#{h cp}'>#{h cn}</a></div>"
    end

    html_page "Folder: #{entry['path']}", out
end

def render_file(db_client, entry)
    # Just dump out metadata hash
    html_page "File: #{entry['path']}", "<pre>#{h entry.pretty_inspect}</pre>"
end

# -------------------------------------------------------------------
# File upload handler

post '/upload' do
    # Check POST parameter.
    file = params[:file]
    unless file && (temp_file = file[:tempfile]) && (name = file[:filename])
        return html_page "Upload error", "<p>No file selected.</p>"
    end

    # Get the DropboxClient object.
    db_client = get_db_client
    unless db_client
        return html_page "Upload error", "<p>Not linked with a Dropbox account.</p>"
    end

    # Call DropboxClient.put_file
    begin
        entry = db_client.put_file("#{params[:folder]}/#{name}", temp_file.read)
    rescue DropboxAuthError => e
        session.delete(:authorized_db_session)  # An auth error means the db_session is probably bad
        return html_page "Dropbox auth error", "<p>#{h e}</p>"
    rescue DropboxError => e
        return html_page "Dropbox API error", "<p>#{h e}</p>"
    end

    html_page "Upload complete", "<pre>#{h entry.pretty_inspect}</pre>"
end

# -------------------------------------------------------------------

def html_page(title, body)
    "<html>" +
        "<head><title>#{h title}</title></head>" +
        "<body><h1>#{h title}</h1>#{body}</body>" +
    "</html>"
end

enable :sessions

helpers do
    include Rack::Utils
    alias_method :h, :escape_html
end

if APP_KEY == '' or APP_SECRET == ''
    puts "You must set APP_KEY and APP_SECRET at the top of \"#{__FILE__}\"!"
    exit 1
end
