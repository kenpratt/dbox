dbox
====

Dropbox integration made easy. This robust client gives you control over what, where, and when you sync with Dropbox.

Available as both a command-line client and a Ruby API.

```sh
$ cd /tmp
$ dbox clone Public
$ cd Public
$ echo "Hello World" > hello.txt
$ dbox sync
[INFO] Uploading /Public/hello.txt
```

**IMPORTANT:** This is **not** an automated Dropbox client. It will exit after sucessfully pushing/pulling, so if you want regular updates, you can run it in cron, a loop, etc. If you do want to run it in a loop, take a look at [sample_polling_script.rb](http://github.com/kenpratt/dbox/blob/master/sample_polling_script.rb). You get deterministic control over what you want Dropbox to do and when you want it to happen.


Installation
------------

### Install dbox

```sh
$ gem install dbox
```

### Get developer keys

* Follow the instructions at https://www.dropbox.com/developers/quickstart to create a Dropbox development application, and copy the application keys. Unless you get your app approved for production status, these keys will only work with the account you create them under, so make sure you are logged in with the account you want to access from ```dbox```.

* Now either set the keys as environment variables:

```sh
$ export DROPBOX_APP_KEY=cmlrrjd3j0gbend
$ export DROPBOX_APP_SECRET=uvuulp75xf9jffl
```

* Or include them in calls to ```dbox```:

```sh
$ DROPBOX_APP_KEY=cmlrrjd3j0gbend DROPBOX_APP_SECRET=uvuulp75xf9jffl dbox ...
```
### Generate an access token

* Make an authorize request:

```sh
$ dbox authorize
1. Go to: https://www.dropbox.com/1/oauth2/authorize?client_id=1x7xvn1pvas3a3&response_type=code
2. Click "Allow" (you might have to log in first)
3. Copy the authorization code
Enter the authorization code here: 
```

* Visit the given URL in your browser, and then go back to the terminal and enter the code that Dropbox provides.

* Now either set the keys as environment variables:

```sh
$ export DROPBOX_ACCESS_TOKEN=aeDsfS4QaReAAAAAAAAAAbZ6nrUUrXZ_Z4Rct2DVTYp6B14N-qiz189gm2VHQqvD
$ export DROPBOX_USER_ID=230324561
```

* Or include the access token in calls to ```dbox```:

```sh
$ DROPBOX_ACCESS_TOKEN=aeDsfS4QaReAAAAAAAAAAbZ6nrUUrXZ_Z4Rct2DVTYp6B14N-qiz189gm2VHQqvD dbox ...
```

* The access token will last for **10 years**, or when you choose to invalidate it, whichever comes first. So you really only need to do this once, and then keep them around.


Using dbox from the Command-Line
--------------------------------

### Usage

#### Authorize

```sh
$ dbox authorize
```

#### Create a new Dropbox folder

```sh
$ dbox create <remote_path> [<local_path>]
```

#### Clone an existing Dropbox folder

```sh
$ dbox clone <remote_path> [<local_path>]
```

#### Pull (download changes from Dropbox)

```sh
$ dbox pull [<local_path>]
```

#### Push (upload changes to Dropbox)

```sh
$ dbox push [<local_path>]
```

#### Sync (pull changes from Dropbox, then push changes to Dropbox)

```sh
$ dbox sync [<local_path>]
```

#### Move (move/rename the Dropbox folder)

```sh
$ dbox move <new_remote_path> [<local_path>]
```

#### Example

```sh
$ export DROPBOX_APP_KEY=cmlrrjd3j0gbend
$ export DROPBOX_APP_SECRET=uvuulp75xf9jffl
```

```sh
$ dbox authorize
```

```sh
$ open http://www.dropbox.com/0/oauth/authorize?oauth_token=aaoeuhtns123456
```

```sh
$ export DROPBOX_ACCESS_TOKEN=aeDsfS4QaReAAAAAAAAAAbZ6nrUUrXZ_Z4Rct2DVTYp6B14N-qiz189gm2VHQqvD
```

```sh
$ cd /tmp
$ dbox clone Public
$ cd Public
$ echo "Hello World" > hello.txt
$ dbox push
```

```sh
$ cat ~/Dropbox/Public/hello.txt
Hello World
$ echo "Oh, Hello" > ~/Dropbox/Public/hello.txt
```

```sh
$ dbox pull
$ cat hello.txt
Oh, Hello
```

Using dbox from Ruby
--------------------

The Ruby clone, pull, and push APIs return a hash of the changes made during that operation. If any failures were encountered while uploading or downloading from Dropbox, they will be shown in the ```:failed``` entry in the hash. Often, trying your operation again will resolve the failures as the Dropbox API occasionally returns errors for valid operations.

```ruby
{ :created => ["foo.txt"], :deleted => [], :updated => [] :failed => [] }
```

If any conflicts occur where file contents would be lost, the conflicting file is renamed and the resulting hash has a ```:conflicts``` entry. On a push operation, the conflicting file being pushed will be renamed. On a pull, the existing file that would have been overwritten will be renamed and the downloaded file will take the name (as that will keep multiple clients in sync).

```ruby
{ :created => [], :updated => [], :deleted => [], :conflicts => [{ :original => "foo.txt", :renamed => "foo (1).txt" }], :failed => [] }
```

The sync API returns a hash with two entries: ```:push``` and ```:pull```, which contain the change hashes for the two operations.

### Usage

#### Setup

* Authorize beforehand with the command-line tool

```ruby
require "dbox"
```

#### Create a new Dropbox folder

```ruby
Dbox.create(remote_path, local_path)
```

#### Clone an existing Dropbox folder

```ruby
Dbox.clone(remote_path, local_path)
```

#### Pull (download changes from Dropbox)

```ruby
Dbox.pull(local_path)
```

#### Push (upload changes to Dropbox)

```ruby
Dbox.push(local_path)
```

#### Sync (pull changes from Dropbox, then push changes to Dropbox)

```ruby
Dbox.sync(local_path)
```

#### Move (move/rename the Dropbox folder)

```ruby
Dbox.move(new_remote_path, local_path)
```

#### Check whether a Dropbox DB file is present

```ruby
Dbox.exists?(local_path)
```

#### Example

```sh
$ export DROPBOX_APP_KEY=cmlrrjd3j0gbend
$ export DROPBOX_APP_SECRET=uvuulp75xf9jffl
```

```sh
$ dbox authorize
```

```sh
$ open http://www.dropbox.com/0/oauth/authorize?oauth_token=aaoeuhtns123456
```

```sh
$ export DROPBOX_ACCESS_TOKEN=aeDsfS4QaReAAAAAAAAAAbZ6nrUUrXZ_Z4Rct2DVTYp6B14N-qiz189gm2VHQqvD
$ export DROPBOX_USER_ID=pqej9rmnj0i1gcxr4
```

```ruby
> require "dbox"
> Dbox.clone("/Public", "/tmp/public")
> File.open("/tmp/public/hello.txt", "w") {|f| f << "Hello World" }
> Dbox.push("/tmp/public")

> File.read("#{ENV['HOME']}/Dropbox/Public/hello.txt")
=> "Hello World"
> File.open("#{ENV['HOME']}/Dropbox/Public/hello.txt", "w") {|f| f << "Oh, Hello" }

> Dbox.pull("/tmp/public")
> File.read("#{ENV['HOME']}/Dropbox/Public/hello.txt")
=> "Oh, Hello"
```
