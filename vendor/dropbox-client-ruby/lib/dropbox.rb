require 'rubygems'
require 'oauth'
require 'json'
require 'uri'
require 'net/http/post/multipart'

class Authenticator

    def initialize(config, key=nil, secret=nil, is_request=false, server=nil)
        @consumer_key = config['consumer_key']
        @consumer_secret = config['consumer_secret']
        @config = config
        @oauth_conf = {
            :site => "http://" + (server || config["server"]),
            :scheme => :header,
            :http_method => :post,
            :request_token_url => config["request_token_url"],
            :access_token_url => config["access_token_url"],
            :authorize_url => config["authorization_url"],
        }

        @consumer = OAuth::Consumer.new @consumer_key, @consumer_secret, @oauth_conf

        @access_token = nil
        @request_token = nil

        if key and secret
          if is_request then
            @request_token = OAuth::RequestToken.new(@consumer, key, secret)
          else
            @access_token = OAuth::AccessToken.new(@consumer, key, secret)
          end            
        end
    end

    attr_reader :config

    def Authenticator.load_config(path)
        open(path) do |f|
            return JSON.parse(f.read())
        end
    end

    def get_request_token(*args)
        @request_token = @consumer.get_request_token(*args)
        return @request_token.authorize_url
    end

    def get_access_token
        if @access_token == nil
            @access_token = @request_token.get_access_token
        end

        return @access_token
    end

    def authorized?
      !!@access_token
    end

    def token
        return (@access_token ||  @request_token).token
    end

    def secret
        return (@access_token || @request_token).secret
    end

    def sign(request, request_options = {})
        return @consumer.sign!(request, @access_token || @request_token, request_options)
    end

    def clone(host)
        return Authenticator.new(@config, token(), secret(), !authorized?, host)
    end
end

# maybe subclass or monkey patch trusted into the oauth stuff


API_VERSION = 0


class DropboxError < RuntimeError
end

class DropboxClient
    attr_reader :token

    def initialize(api_host, content_host, port, auth)
        @api_host = api_host
        @content_host = content_host
        @port = port.to_i
        @auth = auth
        @token = auth.get_access_token
    end

    def initialize_copy(other)
        @token = other.token.clone()
        @token.consumer = @token.consumer.clone()
        @token.consumer.http = nil
    end

    def parse_response(response, callback=nil)
        if response.kind_of?(Net::HTTPServerError)
            raise DropboxError.new("Invalid response #{response}\n#{response.body}")
        elsif not response.kind_of?(Net::HTTPSuccess)
            return response
        end

        if callback
            return response.body
        else
            begin
                return JSON.parse(response.body)
            rescue JSON::ParserError
                return response.body
            end
        end
    end


    def account_info(status_in_response=false, callback=nil)
        response = @token.get build_url(@api_host, @port, "/account/info")
        return parse_response(response, callback)
    end

    def put_file(root, to_path, name, file_obj)
        path = "/files/#{root}#{to_path}"
        oauth_params = {"file" => name}
        auth = @auth.clone(@content_host)

        url = URI.parse(build_url(@content_host, @port, path))

        oauth_fake_req = Net::HTTP::Post.new(url.path)
        oauth_fake_req.set_form_data({ "file" => name })
        auth.sign(oauth_fake_req)

        oauth_sig = oauth_fake_req.to_hash['authorization']

        req = Net::HTTP::Post::Multipart.new(url.path, {
            "file" => UploadIO.new(file_obj, "application/octet-stream", name),
        })
        req['authorization'] = oauth_sig.join(", ")

        res = Net::HTTP.start(url.host, url.port) do |http|
            return parse_response(http.request(req))
        end
    end

    def get_file(root, from_path)
        path = "/files/#{root}#{from_path}"
        response = @token.get(build_url(@content_host, @port, path))
        return parse_response(response, callback=true)
    end

    def file_copy(root, from_path, to_path, callback=nil)
        params = {
            "root" => root,
            "from_path" => from_path, 
            "to_path" => to_path,
            "callback" => callback
        }
        response = @token.post(build_url(@api_host, @port, "/fileops/copy"), params)
        return parse_response(response, callback)
    end

    def file_create_folder(root, path, callback=nil)
        params = {
            "root" => root, 
            "path" => path, 
            "callback" => callback
        }
        response = @token.post(build_url(@api_host, @port, "/fileops/create_folder"), params)

        return parse_response(response, callback)
    end

    def file_delete(root, path, callback=nil)
        params = {
            "root" => root, 
            "path" => path, 
            "callback" => callback
        }
        response = @token.post(build_url(@api_host, @port, "/fileops/delete"), params)
        return parse_response(response, callback)
    end

    def file_move(root, from_path, to_path, callback=nil)
        params = {
            "root" => root,
            "from_path" => from_path, 
            "to_path" => to_path,
            "callback" => callback
        }
        response = @token.post(build_url(@api_host, @port, "/fileops/move"), params)
        return parse_response(response, callback)
    end

    def metadata(root, path, file_limit=10000, hash=nil, list=true, status_in_response=false, callback=nil)
        params = {
            "file_limit" => file_limit.to_s,
            "list" => list ? "true" : "false",
            "status_in_response" => status_in_response ? "true" : "false"
        }
        params["hash"] = hash if hash
        params["callback"] = callback if callback

        response = @token.get build_url(@api_host, @port, "/metadata/#{root}#{path}", params=params)
        return parse_response(response, callback)
    end

    def links(root, path)
        full_path = "/links/#{root}#{path}"
        return build_url(@api_host, @port, full_path)
    end

    def build_url(host, port, url, params=nil)
        port = port == 80 ? nil : port
        versioned_url = "/#{API_VERSION}#{url}"

        target = URI::Generic.new("http", nil, host, port, nil, versioned_url, nil, nil, nil)

        if params
            target.query = params.collect {|k,v| URI.escape(k) + "=" + URI.escape(v) }.join("&")
        end

        return target.to_s
    end


end

