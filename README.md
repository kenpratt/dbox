Simple Dropbox
==============

A painless way to push and pull your Dropbox folders, with fine-grained control over what folder you are syncing, where you are syncing it to, and when you are doing it.

**IMPORTANT:** This is **not** an automated Dropbox client. It will exit after sucessfully pushing/pulling, so if you want regular updates, you can run it in cron, a loop, etc.


Installation
------------

### Get developer keys

* Follow the instructions at https://www.dropbox.com/developers/quickstart create a Dropbox development application, and copy the app keys into a new config file:

<pre>
$ cp config/dropbox.json.example config/dropbox.json
$ edit config/dropbox.json
  "consumer_key": "<your_consumer_key>",
  "consumer_secret": "<your_consumer_secret>",
</pre>

### Generate auth token

<pre>
$ simple-dropbox authorize
Please visit the following URL in your browser, log into Dropbox, and authorize the app you created.

http://www.dropbox.com/0/oauth/authorize?oauth_token=oeunsth23censth

When you have done so, press [ENTER] to continue.

export DROPBOX_AUTH_KEY=abcdef012345678
export DROPBOX_AUTH_SECRET=0123456789abcdefg

This auth token will last for 10 years, or when you choose to invalidate it, whichever comes first.

Now either include these constants in yours calls to simple-dropbox, or set them as environment variables. In bash, including them in calls looks like:
$ DROPBOX_AUTH_KEY="abcdef012345678" DROPBOX_AUTH_SECRET="0123456789abcdefg" simple-dropbox ...
</pre>


Usage
-----

### Authorize

<pre>
$ simple-dropbox authorize
</pre>

### Clone an existing Dropbox folder

<pre>
$ simple-dropbox clone <remote_path> [<local_path>]
</pre>

### Create a new Dropbox folder

<pre>
$ simple-dropbox create <remote_path> [<local_path>]
</pre>

### Pull (download changes from Dropbox)

<pre>
$ simple-dropbox pull
</pre>

### Push (upload changes to Dropbox)

<pre>
$ simple-dropbox push
</pre>


Example
-------

<pre>
$ simple-dropbox authorize
(visit website, come back and press enter)

$ export DROPBOX_AUTH_KEY=abcdef012345678
$ export DROPBOX_AUTH_SECRET=0123456789abcdefg

$ cd /tmp
$ simple-dropbox clone Public
$ cd Public
$ echo "hello world" > hello.txt
$ simple-dropbox push

(now edit hello.txt from your dropbox folder)
$ simple-dropbox pull
$ cat hello.txt
