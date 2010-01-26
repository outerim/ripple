# Copyright 2010 Sean Cribbs, Sonian Inc., and Basho Technologies, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
require 'riak'

module Riak
  # Class for invoking map-reduce jobs using the HTTP interface.
  class MapReduce

    # @return [Array<[bucket,key]>] The bucket/keys for input to the job.
    # @see {#add}
    attr_accessor :inputs

    # @return [Array<Phase>] The map and reduce phases that will be executed
    # @see {#map}
    # @see {#reduce}
    # @see {#link}
    attr_accessor :query
    
    # Creates a new map-reduce job.
    # @param [Client] client the Riak::Client interface
    def initialize(client)
      @client, @inputs, @query = client, [], []
    end
    
    # Add or replace inputs for the job.
    # @overload add(bucket)
    #   Run the job across all keys in the bucket.  This will replace any other inputs previously added.
    #   @param [String, Bucket] bucket the bucket to run the job on
    # @overload add(bucket,key)
    #   Add a bucket/key pair to the job.
    #   @param [String,Bucket] bucket the bucket of the object
    #   @param [String] key the key of the object
    # @overload add(object)
    #   Add an object to the job (by its bucket/key)
    #   @param [RObject] object the object to add to the inputs
    # @overload add(bucket, key, keydata)
    #   @param [String,Bucket] bucket the bucket of the object
    #   @param [String] key the key of the object
    #   @param [String] keydata extra data to pass along with the object to the job
    # @return [MapReduce] self
    def add(*params)
      params = params.dup.flatten
      case params.size
      when 1
        p = params.first
        case p
        when Bucket
          @inputs = p.name
        when RObject
          @inputs << [p.bucket.name, p.key]
        when String
          @inputs = p
        end
      when 2..3
        bucket = params.shift
        bucket = bucket.name if Bucket === bucket
        @inputs << params.unshift(bucket)
      end
      self
    end

    # Add a map phase to the job.
    # @overload map(function)
    #   @param [String, Array] function a Javascript function that represents the phase, or an Erlang [module,function] pair
    # @overload map(function?, options)
    #   @param [String, Array] function a Javascript function that represents the phase, or an Erlang [module, function] pair
    #   @param [Hash] options extra options for the phase (see {Phase#new})
    # @return [MapReduce] self
    # @see {Phase#new}
    def map(*params)
      options = params.extract_options!
      @query << Phase.new({:type => :map, :function => params.shift}.merge(options))
      self
    end
    
    # Add a reduce phase to the job.
    # @overload reduce(function)
    #   @param [String, Array] function a Javascript function that represents the phase, or an Erlang [module,function] pair
    # @overload reduce(function?, options)
    #   @param [String, Array] function a Javascript function that represents the phase, or an Erlang [module, function] pair
    #   @param [Hash] options extra options for the phase (see {Phase#new})
    # @return [MapReduce] self
    # @see {Phase#new}
    def reduce(*params)
      options = params.extract_options!
      @query << Phase.new({:type => :reduce, :function => params.shift}.merge(options))
      self
    end

    # Add a link phase to the job. Link phases follow links attached to objects automatically (a special case of map).
    # @overload link(walk_spec, options={})
    #   @param [WalkSpec] walk_spec a WalkSpec that represents the types of links to follow
    #   @param [Hash] options extra options for the phase (see {Phase#new})
    # @overload link(bucket, tag, keep, options={})
    #   @param [String, nil] bucket the bucket to limit links to
    #   @param [String, nil] tag the tag to limit links to
    #   @param [Boolean] keep whether to keep results of this phase (overrides the phase options)
    #   @param [Hash] options extra options for the phase (see {Phase#new})
    # @overload link(options)
    #   @param [Hash] options options for both the walk spec and link phase
    #   @see {WalkSpec#new}
    # @return [MapReduce] self
    # @see {Phase#new}
    def link(*params)
      options = params.extract_options!
      walk_spec_options = options.slice!(:type, :function, :language, :arg) unless params.first
      walk_spec = WalkSpec.normalize(params.shift || walk_spec_options).first
      @query << Phase.new({:type => :link, :function => walk_spec}.merge(options))
      self
    end

    # Convert the job to JSON for submission over the HTTP interface.
    # @return [String] the JSON representation
    def to_json(options={})
      {"inputs" => inputs, "query" => query}.to_json(options)
    end
    
    # Represents an individual phase in a map-reduce pipeline. Generally you'll want to call
    # methods of {MapReduce} instead of using this directly.
    class Phase
      # @return [Symbol] the type of phase - :map, :reduce, or :link
      attr_accessor :type

      # @return [String, Array<String, String>, Hash, WalkSpec] For :map and :reduce types, the Javascript function to run (as a string or hash with bucket/key), or the module + function in Erlang to run. For a :link type, a {Riak::WalkSpec} or an equivalent hash.
      attr_accessor :function

      # @return [String] the language of the phase's function - "javascript" or "erlang"
      attr_accessor :language

      # @return [Boolean] whether results of this phase will be returned
      attr_accessor :keep

      # @return [Array] any extra static arguments to pass to the phase
      attr_accessor :arg
      
      # Creates a phase in the map-reduce pipeline
      # @param [Hash] options options for the phase
      # @option options [Symbol] :type one of :map, :reduce, :link
      # @option options [String] :language ("javascript") "erlang" or "javascript"
      # @option options [String, Array, Hash] :function In the case of Javascript, a literal function in a string, or a hash with :bucket and :key. In the case of Erlang, an Array of [module, function].  For a :link phase, a hash including any of :bucket, :tag or a WalkSpec.
      # @options options [Boolean] :keep (false) whether to return the results of this phase
      # @options options [Array] :arg (nil) any extra static arguments to pass to the phase
      def initialize(options={})
        self.type = options[:type]
        self.language = options[:language] || "javascript"
        self.function = options[:function]
        self.keep = options[:keep] || false
        self.arg = options[:arg]
      end
      
      def type=(value)
        raise ArgumentError, "type must be :map, :reduce, or :link" unless value.to_s =~ /^(map|reduce|link)$/i
        @type = value.to_s.downcase.to_sym
      end
      
      def function=(value)
        case value
        when Array
          raise ArgumentError, "function must have two elements when an array" unless value.size == 2
          @language = "erlang"
        when Hash
          raise ArgumentError, "function must have :bucket and :key when a hash" unless type == :link || value.has_key?(:bucket) && value.has_key?(:key)
          @language = "javascript"
        when String
          @language = "javascript"
        when WalkSpec
          raise ArgumentError, "WalkSpec is only valid for a function when the type is :link" unless type == :link
        else
          raise ArgumentError, "invalid value for function: #{value.inspect}"
        end        
        @function = value
      end

      def to_json(options={})
        obj = case type
              when :map, :reduce
                defaults = {"language" => language, "keep" => keep}
                case function
                when Hash
                  defaults.merge(function)
                when String
                  defaults.merge("source" => function)                  
                when Array
                  defaults.merge("module" => function[0], "function" => function[1])
                end
              when :link
                spec = WalkSpec.normalize(function).first
                {"bucket" => spec.bucket, "tag" => spec.tag, "keep" => spec.keep || keep}
              end
        obj["arg"] = arg if arg
        { type => obj }.to_json(options)
      end
    end
  end
end