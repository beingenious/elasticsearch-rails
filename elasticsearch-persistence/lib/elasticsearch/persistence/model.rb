require 'active_support/core_ext/module/delegation'

require 'active_model'

require 'elasticsearch/persistence'
require 'elasticsearch/persistence/model/base'
require 'elasticsearch/persistence/model/errors'
require 'elasticsearch/persistence/model/store'
require 'elasticsearch/persistence/model/find'
require 'elasticsearch/persistence/model/dirty'

module Elasticsearch
  module Persistence

    # Boolean type placeholder (replaces Virtus::Attribute::Boolean)
    # Used by attribute declarations: `attribute :enabled, Boolean`
    module Boolean; end

    module Model
      def self.included(base)
        base.class_eval do
          include ActiveModel::Naming
          include ActiveModel::Conversion
          include ActiveModel::Serialization
          include ActiveModel::Serializers::JSON
          include ActiveModel::Validations
          include ActiveModel::Dirty
          include ActiveModel::Attributes
          include ActiveModel::AttributeAssignment

          extend  ActiveModel::Callbacks
          define_model_callbacks :create, :save, :update, :destroy, :validation
          define_model_callbacks :find, :touch, only: :after

          include Elasticsearch::Persistence::Model::Base::InstanceMethods

          extend  Elasticsearch::Persistence::Model::Store::ClassMethods
          include Elasticsearch::Persistence::Model::Store::InstanceMethods

          extend  Elasticsearch::Persistence::Model::Find::ClassMethods

          extend  Elasticsearch::Persistence::Model::Dirty::ClassMethods
          include Elasticsearch::Persistence::Model::Dirty::InstanceMethods

          class << self
            def virtus_default_procs
              @virtus_default_procs ||= {}
            end

            # Attribute method compatible with the Virtus-style API:
            #   attribute :name, String, default: 'foo', mapping: { type: 'keyword' }
            #
            # Translates Ruby types (String, Integer, etc.) to ActiveModel attribute types
            # and configures Elasticsearch mapping.
            #
            def attribute(name, type=nil, options={}, &block)
              mapping = options.delete(:mapping) || {}
              virtus_default_procs.delete(name.to_s)

              # Translate Ruby class types to ActiveModel::Attributes type symbols
              am_type = Utils.ruby_type_to_am_type(type)

              # Handle defaults: ActiveModel needs procs for mutable defaults
              if options.key?(:default)
                default = options.delete(:default)
                if default.is_a?(Proc)
                  virtus_default_procs[name.to_s] = default
                  super(name, am_type)
                elsif default.is_a?(Hash) || default.is_a?(Array)
                  mutable_default = default
                  default = -> { Utils.deep_dup(mutable_default) }
                  super(name, am_type, **{ default: default })
                else
                  super(name, am_type, **{ default: default })
                end
              else
                super(name, am_type)
              end

              gateway.mapping do
                indexes name, {type: Utils::lookup_type(type)}.merge(mapping)
              end

              gateway.mapping(&block) if block_given?
            end

            # Return the {Repository::Class} instance
            #
            def gateway(&block)
              @gateway ||= Elasticsearch::Persistence::Repository::Class.new host: self
              block.arity < 1 ? @gateway.instance_eval(&block) : block.call(@gateway) if block_given?
              @gateway
            end

            DEPRECATION_WARNING = "This (ActiveRecord) persistence pattern is deprecated. It will be removed in " +
              "version 6.0 in favor of the Repository pattern. Please see the ReadMe for " +
              "details on the alternative pattern.\n" +
              "https://github.com/elastic/elasticsearch-rails/tree/master/elasticsearch-persistence" +
              "#the-repository-pattern".freeze

            # Warn that this ActiveRecord persistence pattern is deprecated.
            #
            def raise_deprecation_warning!
              if STDERR.tty?
                Kernel.warn("\e[31;1m#{DEPRECATION_WARNING}\e[0m")
              else
                Kernel.warn(DEPRECATION_WARNING)
              end
            end

            # Delegate methods to repository
            #
            delegate :settings,
                     :mappings,
                     :mapping,
                     :document_type=,
                     :index_name,
                     :index_name=,
                     :find,
                     :exists?,
                     :create_index!,
                     :refresh_index!,
              to: :gateway

            # forward document type to mappings when set
            def document_type(type = nil)
              return gateway.document_type unless type
              gateway.document_type type
              mapping.type = type
            end
          end

          # Configure the repository based on the model (set up index_name, etc)
          #
          gateway do
            klass         base
            index_name    base.model_name.collection.gsub(/\//, '-')
            document_type base.model_name.element

            def serialize(document)
              document.to_hash.except(:id, 'id')
            end

            def deserialize(document)
              object = klass.new document['_source']

              # Set the meta attributes when fetching the document from Elasticsearch
              #
              object.instance_variable_set :@_id,      document['_id']
              object.instance_variable_set :@_index,   document['_index']
              object.instance_variable_set :@_type,    document['_type']
              object.instance_variable_set :@_version, document['_version']
              object.instance_variable_set :@_source,  document['_source']

              # Store the "hit" information (highlighting, score, ...)
              #
              object.instance_variable_set :@hit,
                 Elasticsearch::Model::HashWrapper.new(document.except('_index', '_type', '_id', '_version', '_source'))

              object.instance_variable_set(:@persisted, true)
              object
            end
          end

          # Set up common attributes
          #
          attribute :created_at, Time, default: lambda { |o,a| Time.now.utc }
          attribute :updated_at, Time, default: lambda { |o,a| Time.now.utc }

          attr_reader :hit

          # raise_deprecation_warning!
        end

      end
    end

  end
end

# Make Boolean available at top level (as Virtus did)
Boolean = Elasticsearch::Persistence::Boolean unless defined?(Boolean)
