require 'rack/utils'

module Faraday
  module AutoloadHelper
    def register_lookup_modules(mods)
      (@lookup_module_index ||= {}).update(mods)
    end

    def lookup_module(key)
      return if !@lookup_module_index
      const_get @lookup_module_index[key] || key
    end

    def autoload_all(prefix, options)
      options.each do |const_name, path|
        autoload const_name, File.join(prefix, path)
      end
    end

    # Loads each autoloaded constant.  If thread safety is a concern, wrap
    # this in a Mutex.
    def load_autoloaded_constants
      constants.each do |const|
        const_get(const) if autoload?(const)
      end
    end

    def all_loaded_constants
      constants.map { |c| const_get(c) }.select { |a| a.loaded? }
    end
  end

  extend AutoloadHelper

  autoload_all 'faraday', 
    :Connection => 'connection',
    :Middleware => 'middleware',
    :Builder    => 'builder',
    :Request    => 'request',
    :Response   => 'response',
    :Error      => 'error'

  module Adapter
    extend AutoloadHelper
    autoload_all 'faraday/adapter',
      :NetHttp  => 'net_http',
      :Typhoeus => 'typhoeus',
      :Patron   => 'patron',
      :Test     => 'test'

    register_lookup_modules \
      :test     => :Test,
      :net_http => :NetHttp,
      :typhoeus => :Typhoeus,
      :patron   => :patron,
      :net_http => :NetHttp
  end
end

# not pulling in active-support JUST for this method.
class Object
  # Yields <code>x</code> to the block, and then returns <code>x</code>.
  # The primary purpose of this method is to "tap into" a method chain,
  # in order to perform operations on intermediate results within the chain.
  #
  #   (1..10).tap { |x| puts "original: #{x.inspect}" }.to_a.
  #     tap    { |x| puts "array: #{x.inspect}" }.
  #     select { |x| x%2 == 0 }.
  #     tap    { |x| puts "evens: #{x.inspect}" }.
  #     map    { |x| x*x }.
  #     tap    { |x| puts "squares: #{x.inspect}" }
  def tap
    yield self
    self
  end unless Object.respond_to?(:tap)
end
