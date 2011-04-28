require 'rubygems'
require 'lib/dropbox'
require 'test/unit'
require 'shoulda'
require './test/util'

CONF = Authenticator.load_config("config/testing.json")

class AuthenticatorTest < Test::Unit::TestCase
  context "Authenticator" do
    should "load json config" do
        assert CONF
        auth = Authenticator.new(CONF)
    end

    should "get request token" do
        auth = Authenticator.new(CONF)
        authorize_url = auth.get_request_token
        assert authorize_url
    end

    should "get access token" do
        auth = Authenticator.new(CONF)
        authorize_url = auth.get_request_token
        assert authorize_url

        login_and_authorize(authorize_url, CONF)

        access_token = auth.get_access_token
        assert access_token

        assert access_token.token
        assert access_token.secret

        CONF['access_token_key'] = access_token.token
        CONF['access_token_secret'] = access_token.secret

        response = access_token.get "http://" + CONF['server'] + "/0/oauth/echo"
        assert response
        assert response.code == "200"
    end

    should "reuse an existing token" do
        auth = Authenticator.new(CONF, CONF['access_token_key'], CONF['access_token_secret'])
        access_token = auth.get_access_token

        response = access_token.get "http://" + CONF['server'] + "/0/oauth/echo"
        assert response
        assert response.code == "200"
    end
  end
end

