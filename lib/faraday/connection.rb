require 'addressable/uri'
require 'set'

module Faraday
  class Connection
    include Addressable, Rack::Utils

    HEADERS = Hash.new { |h, k| k.respond_to?(:to_str) ? k : k.to_s.capitalize }.update \
      :content_type    => "Content-Type",
      :content_length  => "Content-Length",
      :accept_charset  => "Accept-Charset",
      :accept_encoding => "Accept-Encoding"
    HEADERS.values.each { |v| v.freeze }

    METHODS = Set.new [:get, :post, :put, :delete, :head]
    METHODS_WITH_BODIES = Set.new [:post, :put]

    attr_accessor :host, :port, :scheme, :params, :headers, :parallel_manager
    attr_reader   :path_prefix, :builder

    # :url
    # :params
    # :headers
    def initialize(url = nil, options = {}, &block)
      if url.is_a?(Hash)
        options = url
        url     = options[:url]
      end
      @headers          = HeaderHash.new
      @params           = {}
      @parallel_manager = options[:parallel]
      self.url_prefix = url if url
      merge_params  @params,  options[:params]  if options[:params]
      merge_headers @headers, options[:headers] if options[:headers]
      if block
        @builder = Builder.create_with_inner_app(&block)
      end
    end

    def get(url = nil, headers = nil, &block)
      run_request :get, url, nil, headers, &block
    end

    def post(url = nil, body = nil, headers = nil, &block)
      run_request :post, url, body, headers, &block
    end

    def put(url = nil, body = nil, headers = nil, &block)
      run_request :put, url, body, headers, &block
    end

    def head(url = nil, headers = nil, &block)
      run_request :head, url, nil, headers, &block
    end

    def delete(url = nil, headers = nil, &block)
      run_request :delete, url, nil, headers, &block
    end

    def run_request(method, url, body, headers)
      if !METHODS.include?(method)
        raise ArgumentError, "unknown http method: #{method}"
      end

      Request.run(self, method) do |req|
        req.url(url)                if url
        req.headers.update(headers) if headers
        req.body = body             if body
        yield req if block_given?
      end
    end

    def in_parallel?
      !!@parallel_manager
    end

    def in_parallel(manager)
      @parallel_manager = manager
      yield
      @parallel_manager && @parallel_manager.run
    ensure
      @parallel_manager = nil
    end

    # return the assembled Rack application for this instance.
    def to_app
      @builder.to_app
    end

    # Parses the giving url with Addressable::URI and stores the individual
    # components in this connection.  These components serve as defaults for 
    # requests made by this connection.
    #
    #   conn = Faraday::Connection.new { ... }
    #   conn.url_prefix = "https://sushi.com/api"
    #   conn.scheme      # => https
    #   conn.path_prefix # => "/api"
    #
    #   conn.get("nigiri?page=2") # accesses https://sushi.com/api/nigiri
    #
    def url_prefix=(url)
      uri              = URI.parse(url)
      self.scheme      = uri.scheme
      self.host        = uri.host
      self.port        = uri.port
      self.path_prefix = uri.path
      if uri.query && !uri.query.empty?
        merge_params @params, parse_query(uri.query)
      end
    end

    # Ensures that the path prefix always has a leading / and no trailing /
    def path_prefix=(value)
      if value
        value.chomp!  "/"
        value.replace "/#{value}" if value !~ /^\//
      end
      @path_prefix = value
    end

    # Takes a relative url for a request and combines it with the defaults 
    # set on the connection instance.
    #
    #   conn = Faraday::Connection.new { ... }
    #   conn.url_prefix = "https://sushi.com/api?token=abc"
    #   conn.scheme      # => https
    #   conn.path_prefix # => "/api"
    #
    #   conn.build_url("nigiri?page=2")      # => https://sushi.com/api/nigiri?token=abc&page=2
    #   conn.build_url("nigiri", :page => 2) # => https://sushi.com/api/nigiri?token=abc&page=2
    #
    def build_url(url, params = nil)
      uri          = URI.parse(url.to_s)
      uri.scheme ||= @scheme
      uri.host   ||= @host
      uri.port   ||= @port
      if @path_prefix && uri.path !~ /^\//
        uri.path = "#{@path_prefix.size > 1 ? @path_prefix : nil}/#{uri.path}"
      end
      replace_query(uri, params)
      uri
    end

    def replace_query(uri, params)
      url_params = @params.dup
      if uri.query && !uri.query.empty?
        merge_params url_params, parse_query(uri.query)
      end
      if params && !params.empty?
        merge_params url_params, params
      end
      uri.query = url_params.empty? ? nil : build_query(url_params)
      uri
    end

    # turns param keys into strings
    def merge_params(existing_params, new_params)
      new_params.each do |key, value|
        existing_params[key.to_s] = value
      end
    end

    # turns headers keys and values into strings.  Look up symbol keys in the 
    # the HEADERS hash.  
    #
    #   h = merge_headers(HeaderHash.new, :content_type => 'text/plain')
    #   h['Content-Type'] # = 'text/plain'
    #
    def merge_headers(existing_headers, new_headers)
      new_headers.each do |key, value|
        existing_headers[HEADERS[key]] = value.to_s
      end
    end

    # Be sure to URI escape '+' symbols to %2B.  Otherwise, they get interpreted
    # as spaces.
    def escape(s)
      s.to_s.gsub(/([^a-zA-Z0-9_.-]+)/n) do
        '%' << $1.unpack('H2'*bytesize($1)).join('%').tap { |c| c.upcase! }
      end
    end
  end
end
