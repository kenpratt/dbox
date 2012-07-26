require './lib/dropbox_sdk'
require 'json'

# You must use your Dropbox App key and secret to use the API.
# Find this at https://www.dropbox.com/developers
APP_KEY = ''
APP_SECRET = ''
ACCESS_TYPE = :app_folder #The two valid values here are :app_folder and :dropbox
                          #The default is :app_folder, but your application might be
                          #set to have full :dropbox access.  Check your app at
                          #https://www.dropbox.com/developers/apps

STATE_FILE = 'copy_between_accounts.json'

def main()
    prog_name = __FILE__
    if APP_KEY == '' or APP_SECRET == ''
        warn "ERROR: Set your APP_KEY and APP_SECRET at the top of #{prog_name}"
        exit
    end
    args = ARGV
    if args.size == 0
        warn("Usage:\n")
        warn("   #{prog_name} link                                   Link to a user's account.  Also displays UID.")
        warn("   #{prog_name} list                                   List linked users including UID.")
        warn("   #{prog_name} copy '<uid>:<path>' '<uid>:<path>'     Copies a file from the first user's path, to the second user's path.")
        warn("\n\n   <uid> is the account UID shown when linked.  <path> is a path to a file on that user's dropbox.")
        exit
    end

    command = args[0]
    if command == 'link'
        command_link(args)
    elsif command == 'list'
        command_list(args)
    elsif command == 'copy'
        command_copy(args)
    else
        warn "ERROR: Unknown command: #{command}"
        warn "Run with no arguments for help."
        exit(1)
    end
end

def command_link(args)
    if args.size != 1
        warn "ERROR: \"link\" doesn't take any arguments"
        exit
    end

    sess = DropboxSession.new(APP_KEY, APP_SECRET)
    sess.get_request_token

    # Make the user log in and authorize this token
    url = sess.get_authorize_url
    puts "1. Go to: #{url}"
    puts "2. Authorize this app."
    puts "After you're done, press ENTER."
    STDIN.gets

    # This will fail if the user didn't visit the above URL and hit 'Allow'
    sess.get_access_token
    access_token = sess.access_token
    c = DropboxClient.new(sess, ACCESS_TYPE)
    account_info = c.account_info()

    puts "Link successful. #{account_info['display_name']} is uid #{account_info['uid']} "

    state = load_state()
    state[account_info['uid']] = {
                    'access_token' => [access_token.key, access_token.secret],
                    'display_name' => account_info['display_name'],
    }

    save_state(state)
end

def command_list(args)
    if args.size != 1
        warn "ERROR: \"list\" doesn't take any arguments"
        exit
    end

    state = load_state()
    for e in state.keys()
        puts "#{state[e]['display_name']} is uid #{e}"
    end
end

def command_copy(args)
    if args.size != 3
        warn "ERROR: \"copy\" takes exactly two arguments"
        exit
    end

    state = load_state()

    if state.keys().length < 2
        warn "ERROR: You can't use the copy command until at least two users have linked"
        exit
    end

    from = args[1].gsub(/['"]/,'')
    to = args[2].gsub(/['"]/,'')

    if not to.index(':') or not from.index(':')
        warn "ERROR: Ill-formated paths. Run #{prog_name} without arugments to see documentation."
        exit
    end

    from_uid, from_path = from.split ":"
    to_uid, to_path = to.split ":"

    if not state.has_key?(to_uid) or not state.has_key?(from_uid)
        warn "ERROR: Those UIDs have not linked.  Run #{prog_name} list to see linked UIDs."
        exit
    end

    from_token = state[from_uid]['access_token']
    to_token = state[to_uid]['access_token']

    from_session = DropboxSession.new(APP_KEY, APP_SECRET)
    to_session = DropboxSession.new(APP_KEY, APP_SECRET)

    from_session.set_access_token(*from_token)
    to_session.set_access_token(*to_token)

    from_client = DropboxClient.new(from_session, ACCESS_TYPE)
    to_client = DropboxClient.new(to_session, ACCESS_TYPE)

    #Create a copy ref under the identity of the from user
    copy_ref = from_client.create_copy_ref(from_path)['copy_ref']

    metadata = to_client.add_copy_ref(to_path, copy_ref)

    puts "File successly copied from #{state[from_uid]['display_name']} to #{state[to_uid]['display_name']}!"
    puts "The file now exists at #{metadata['path']}"

end

def save_state(state)
    File.open(STATE_FILE,"w") do |f|
        f.write(JSON.pretty_generate(state))
    end
end

def load_state()
    if not FileTest.exists?(STATE_FILE)
        return {}
    end
    JSON.parse(File.read(STATE_FILE))
end


main()
