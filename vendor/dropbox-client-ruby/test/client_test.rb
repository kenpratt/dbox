require 'rubygems'
require 'lib/dropbox'
require 'test/unit'
require 'shoulda'
require './test/util'
require 'pp'

CONF = Authenticator.load_config("config/testing.json") unless defined?(CONF)
AUTH = Authenticator.new(CONF) unless defined?(AUTH)
login_and_authorize(AUTH.get_request_token, CONF)
ACCESS_TOKEN = AUTH.get_access_token


class DropboxClientTest < Test::Unit::TestCase

    context "DropboxClient" do
        setup do
            assert ACCESS_TOKEN
            assert AUTH
            assert CONF

            begin
                client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
                client.file_delete(CONF['root'], "/tests")
            rescue
                # ignored
            end
        end

        should "be able to access account info" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
            info = client.account_info
            assert info
            assert info["country"]
            assert info["uid"]
        end

        should "build full urls" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
            url = client.build_url(CONF['server'], CONF['port'], "/account/info")
            assert_equal url, "http://" + CONF['server'] + "/0/account/info"

            url = client.build_url(CONF['server'], CONF['port'], "/account/info")
            assert_equal url, "http://" + CONF['server'] + "/0/account/info"

            url = client.build_url(CONF['server'], CONF['port'], "/account/info", params={"one" => "1", "two" => "2"})
            assert_equal url, "http://" + CONF['server'] + "/0/account/info?two=2&one=1"

            url = client.build_url(CONF['server'], CONF['port'], "/account/info", params={"one" => "1", "two" => "2"})
            assert_equal url, "http://" + CONF['server'] + "/0/account/info?two=2&one=1"
        end


        should "create links" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'] ,CONF['port'], AUTH)
            assert_equal "http://" + CONF['server'] + "/0/links/" + CONF['root'] + "/to/the/file", client.links(CONF['root'], "/to/the/file")
        end

        should "get metadata" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'] ,CONF['port'], AUTH)
            results = client.metadata(CONF['root'], "/")
            assert results
            assert results["hash"]
        end

        should "be able to perform file ops on folders" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
            results = client.file_create_folder(CONF['root'], "/tests/that")
            assert results
            assert results["bytes"]

            assert client.file_copy(CONF['root'], "/tests/that", "/tests/those")
            assert client.metadata(CONF['root'], "/tests/those")
            assert client.file_delete(CONF['root'], "/tests/those")

            results = client.file_move(CONF['root'], "/tests/that", "/tests/those")
            assert results

            assert client.metadata(CONF['root'], "/tests/those")
            assert client.file_delete(CONF['root'], "/tests/those")

        end
       
        should "be able to get files" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
            results = client.get_file(CONF['root'], "/client_tests.py")
            assert results
        end

        should "be able to put files" do
            client = DropboxClient.new(CONF['server'], CONF['content_server'], CONF['port'], AUTH)
            results = client.put_file(CONF['root'], "/", "LICENSE", open("LICENSE"))
            assert results
            assert client.file_delete(CONF['root'], "/LICENSE")
        end

    end

end

