dbox
====

A painless way to push and pull your Dropbox folders, with fine-grained control over what folder you are syncing, where you are syncing it to, and when you are doing it.

**IMPORTANT:** This is **not** an automated Dropbox client. It will exit after sucessfully pushing/pulling, so if you want regular updates, you can run it in cron, a loop, etc.


Installation
------------

### Get developer keys

* Follow the instructions at https://www.dropbox.com/developers/quickstart create a Dropbox development application, and copy the app keys into a new config file:

```sh
$ cp config/dropbox.json.example config/dropbox.json
$ edit config/dropbox.json
  "consumer_key": "<your_consumer_key>",
  "consumer_secret": "<your_consumer_secret>",
```

### Generate auth token

```sh
$ dbox authorize
Please visit the following URL in your browser, log into Dropbox, and authorize the app you created.

http://www.dropbox.com/0/oauth/authorize?oauth_token=j2kuzfvobcpqh0g

When you have done so, press [ENTER] to continue.

export DROPBOX_AUTH_KEY=abcdef012345678
export DROPBOX_AUTH_SECRET=0123456789abcdefg

This auth token will last for 10 years, or when you choose to invalidate it, whichever comes first.

Now either include these constants in yours calls to dbox, or set them as environment variables.
In bash, including them in calls looks like:
$ DROPBOX_AUTH_KEY=abcdef012345678 DROPBOX_AUTH_SECRET=0123456789abcdefg dbox ...
```


Usage
-----

### Authorize

```sh
$ dbox authorize
```

### Clone an existing Dropbox folder

```sh
$ dbox clone <remote_path> [<local_path>]
```

### Create a new Dropbox folder

```sh
$ dbox create <remote_path> [<local_path>]
```

### Pull (download changes from Dropbox)

```sh
$ dbox pull [<local_path>]
```

### Push (upload changes to Dropbox)

```sh
$ dbox push [<local_path>]
```


Example
-------

```sh
$ dbox authorize
```

(visit website to authorize)

```sh
$ export DROPBOX_AUTH_KEY=abcdef012345678
$ export DROPBOX_AUTH_SECRET=0123456789abcdefg
```

```sh
$ cd /tmp
$ dbox clone Public
$ cd Public
$ echo "hello world" > hello.txt
$ dbox push
```

(edit hello.txt from your dropbox folder, changing the content to "oh, hello there")

```sh
$ dbox pull
$ cat hello.txt
```
