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

DROPBOX_AUTH_KEY=abcdef012345678
DROPBOX_AUTH_SECRET=0123456789abcdefg

This auth token will last for 10 years, or when you choose to invalidate it, whichever comes first.

Now either include these constants in yours calls to simple-dropbox, or set them as environment variables.
</pre>


Usage
-----

### Authorize

<pre>
$ simple-dropbox authorize
</pre>

### Pull using paths set in config file

<pre>
$ DROPBOX_AUTH_KEY="abcdef012345678" DROPBOX_AUTH_SECRET="0123456789abcdefg" simple-dropbox pull
</pre>

### Push using paths set in config file

<pre>
$ DROPBOX_AUTH_KEY="abcdef012345678" DROPBOX_AUTH_SECRET="0123456789abcdefg" simple-dropbox push
</pre>

### Pull using custom paths

<pre>
$ DROPBOX_AUTH_KEY="abcdef012345678" DROPBOX_AUTH_SECRET="0123456789abcdefg" simple-dropbox pull -r /Custom -l /path/to/custom
</pre>

### Push using custom paths

<pre>
$ DROPBOX_AUTH_KEY="abcdef012345678" DROPBOX_AUTH_SECRET="0123456789abcdefg" simple-dropbox push -r /Custom -l /path/to/custom
</pre>
