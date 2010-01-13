module Faraday
  class Response::Yajl < Response::Middleware
    begin
      require 'yajl'

      def self.register_on_complete(env)
        env[:response].on_complete do |finished_env|
          finished_env[:body] = Yajl::Parser.parse(finished_env[:body])
        end
      end
    rescue LoadError => e
      self.load_error = e
    end
    
    def initialize(app)
      super
      @parser = nil
    end
  end
end
