# An example use of the /delta API call.  Maintains a local cache of
# the App Folder's contents.  Use the 'update' sub-command to update
# the local cache.  Use the 'find' sub-command to search the local
# cache.
#
# Example usage:
#
# 1. Link to your Dropbox account
#    > ruby search_cache.rb link
#
# 2. Go to Dropbox and make changes to the contents.
#
# 3. Update the local cache to match what's on Dropbox.
#    > ruby search_cache.rb update
#
# 4. Search the local cache.
#    > ruby search_cache.rb find 'txt'

# Repeat steps 2-4 any number of times.



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


STATE_FILE = 'search_cache.json'

def main()
    if APP_KEY == '' or APP_SECRET == ''
        warn "ERROR: Set your APP_KEY and APP_SECRET at the top of search_cache.rb"
        exit
    end
    prog_name = __FILE__
    args = ARGV
    if args.size == 0
        warn("Usage:\n")
        warn("   #{prog_name} link          Link to a user's account.")
        warn("   #{prog_name} update        Update cache to the latest on Dropbox.")
        warn("   #{prog_name} update <num>  Update cache, limit to <num> pages of /delta.")
        warn("   #{prog_name} find <term>   Search cache for <term>.")
        warn("   #{prog_name} find          Display entire cache contents")
        warn("   #{prog_name} reset         Delete the cache.")
        exit
    end

    command = args[0]
    if command == 'link'
        command_link(args)
    elsif command == 'update'
        command_update(args)
    elsif command == 'find'
        command_find(args)
    elsif command == 'reset'
        command_reset(args)
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
    puts "Link successful."

    save_state({
        'access_token' => [access_token.key, access_token.secret],
        'tree' => {}
    })
end


def command_update(args)
    if args.size == 1
        page_limit = nil
    elsif args.size == 2
        page_limit = Integer(args[1])
    else
        warn "ERROR: \"update\" takes either zero or one argument."
        exit
    end

    # Load state
    state = load_state()
    access_token = state['access_token']
    cursor = state['cursor']
    tree = state['tree']

    # Connect to Dropbox
    sess = DropboxSession.new(APP_KEY, APP_SECRET)
    sess.set_access_token(*access_token)
    c = DropboxClient.new(sess, ACCESS_TYPE)

    page = 0
    changed = false
    while (page_limit == nil) or (page < page_limit)
        # Get /delta results from Dropbox
        result = c.delta(cursor)
        page += 1
        if result['reset'] == true
            puts 'reset'
            changed = true
            tree = {}
        end
        cursor = result['cursor']
        # Apply the entries one by one to our cached tree.
        for delta_entry in result['entries']
            changed = true
            apply_delta(tree, delta_entry)
        end
        cursor = result['cursor']
        if not result['has_more']
            break
        end
    end

    # Save state
    if changed
        state['cursor'] = cursor
        state['tree'] = tree
        save_state(state)
    else
        puts "No updates."
    end

end

# We track folder state as a tree of Node objects.
class Node
    attr_accessor :path, :content
    def initialize(path, content)
        # The "original" page (i.e. not the lower-case path)
        @path = path
        # For files, content is a pair (size, modified)
        # For folders, content is a hash of children Nodes, keyed by lower-case file names.
        @content = content
    end
    def folder?()
        @content.is_a? Hash
    end
    def to_json()
        [@path, Node.to_json_content(@content)]
    end
    def self.from_json(jnode)
        path, jcontent = jnode
        Node.new(path, Node.from_json_content(jcontent))
    end
    def self.to_json_content(content)
        if content.is_a? Hash
            map_hash_values(content) { |child| child.to_json }
        else
            content
        end
    end
    def self.from_json_content(jcontent)
        if jcontent.is_a? Hash
            map_hash_values(jcontent) { |jchild| Node.from_json jchild }
        else
            jcontent
        end
    end
end

# Run a mapping function over every value in a Hash, returning a new Hash.
def map_hash_values(h)
    new = {}
    h.each { |k,v| new[k] = yield v }
    new
end


def apply_delta(root, e)
    path, metadata = e
    branch, leaf = split_path(path)

    if metadata != nil
        puts "+ #{path}"
        # Traverse down the tree until we find the parent folder of the entry
        # we want to add.  Create any missing folders along the way.
        children = root
        branch.each do |part|
            node = get_or_create_child(children, part)
            # If there's no folder here, make an empty one.
            if not node.folder?
                node.content = {}
            end
            children = node.content
        end

        # Create the file/folder.
        node = get_or_create_child(children, leaf)
        node.path = metadata['path']  # Save the un-lower-cased path.
        if metadata['is_dir']
            # Only create a folder if there isn't one there already.
            node.content = {} if not node.folder?
        else
            node.content = metadata['size'], metadata['modified']
        end
    else
        puts "- #{path}"
        # Traverse down the tree until we find the parent of the entry we
        # want to delete.
        children = root
        missing_parent = false
        branch.each do |part|
            node = children[part]
            # If one of the parent folders is missing, then we're done.
            if node == nil or not node.folder?
                missing_parent = true
                break
            end
            children = node.content
        end
        # If we made it all the way, delete the file/folder.
        if not missing_parent
            children.delete(leaf)
        end
    end
end

def get_or_create_child(children, name)
    child = children[name]
    if child == nil
        children[name] = child = Node.new(nil, nil)
    end
    child
end

def split_path(path)
    bad, *parts = path.split '/'
    [parts, parts.pop]
end


def command_find(args)
    if args.size == 1
        term = ''
    elsif args.size == 2
        term = args[1]
    else
        warn("ERROR: \"find\" takes either zero or one arguments.")
        exit
    end

    state = load_state()
    results = []
    search_tree(results, state['tree'], term)
    for r in results
        puts("#{r}")
    end
    puts("[Matches: #{results.size}]")
end


def command_reset(args)
    if args.size != 1
        warn("ERROR: \"reset\" takes no arguments.")
        exit
    end

    # Delete cursor, empty tree.
    state = load_state()
    if state.has_key?('cursor')
        state.delete('cursor')
    end
    state['tree'] = {}
    save_state(state)
end


# Recursively search 'tree' for files that contain the string in 'term'.
# Print out any matches.
def search_tree(results, tree, term)
    tree.each do |name_lc, node|
        path = node.path
        if (path != nil) and path.include?(term)
            if node.folder?
                results.push("#{path}")
            else
                size, modified = node.content
                results.push("#{path}  (#{size}, #{modified})")
            end
        end
        if node.folder?
            search_tree(results, node.content, term)
        end
    end
end

def save_state(state)
    state['tree'] = Node.to_json_content(state['tree'])
    File.open(STATE_FILE,"w") do |f|
        f.write(JSON.pretty_generate(state, :max_nesting => false))
    end
end

def load_state()
    state = JSON.parse(File.read(STATE_FILE), :max_nesting => false)
    state['tree'] = Node.from_json_content(state['tree'])
    state
end

main()
