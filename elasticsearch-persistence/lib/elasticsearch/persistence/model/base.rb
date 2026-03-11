module Elasticsearch
  module Persistence
    module Model
      # This module contains the base interface for models
      #
      module Base
        module InstanceMethods

          # Model initializer sets the `@id` variable if passed
          #
          def initialize(attributes={})
            # Normalize string keys to symbols
            normalized = {}
            attributes.each do |k, v|
              normalized[k.to_sym] = v
            end

            @_id = normalized.delete(:id)

            # Initialize ActiveModel::Attributes with defaults (no args)
            super()

            # Then assign known attributes via setters
            normalized.each do |k, v|
              if self.class.attribute_types.key?(k.to_s)
                send("#{k}=", v)
              end
            end

            apply_virtus_default_procs(normalized)
          end

          # Return model attributes as a Hash, merging in the `id`
          #
          def attributes
            super.symbolize_keys.merge(id: id)
          end

          # Return attributes as a Hash (Virtus compatibility)
          #
          def to_hash
            attributes
          end

          # Override attributes= to silently ignore unknown attributes (Virtus behavior)
          #
          def attributes=(new_attributes)
            return unless new_attributes.is_a?(Hash)
            known = new_attributes.select { |k, _| self.class.attribute_types.key?(k.to_s) }
            super(known)
          end

          # Bracket reader for attribute access: model[:name]
          # Returns nil for unknown keys (Virtus behavior)
          #
          def [](key)
            return nil unless respond_to?(key)
            send(key)
          end

          # Bracket writer for attribute access: model[:name] = value
          # Silently ignores unknown keys (Virtus behavior)
          #
          def []=(key, value)
            setter = "#{key}="
            return unless respond_to?(setter)
            send(setter, value)
          end

          # Return the document `_id`
          #
          def id
            @_id
          end; alias :_id :id

          # Set the document `_id`
          #
          def id=(value)
            @_id = value
          end; alias :_id= :id=

          # Return the document `_index`
          #
          def _index
            @_index
          end

          # Return the document `_type`
          #
          def _type
            @_type
          end

          # Return the document `_version`
          #
          def _version
            @_version
          end

          # Return the raw document `_source`
          #
          def _source
            @_source
          end

          def to_s
            "#<#{self.class} #{attributes.to_hash.inspect.gsub(/:(\w+)=>/, '\1: ')}>"
          end; alias :inspect :to_s

          private

          def apply_virtus_default_procs(normalized_attributes)
            return unless self.class.respond_to?(:virtus_default_procs)

            self.class.virtus_default_procs.each do |name, default_proc|
              next if normalized_attributes.key?(name.to_sym)
              next unless self.class.attribute_types.key?(name)

              send("#{name}=", Utils.evaluate_default_proc(self, name, default_proc))
            end
          end
        end
      end

      # Utility methods for {Elasticsearch::Persistence::Model}
      #
      module Utils
        DefaultAttribute = Struct.new(:name)

        def deep_dup(value)
          case value
            when Array
              value.map { |item| deep_dup(item) }
            when Hash
              value.each_with_object({}) do |(key, item), duplicate|
                duplicate[deep_dup(key)] = deep_dup(item)
              end
            else
              value.dup
          end
        rescue TypeError, NoMethodError
          value
        end; module_function :deep_dup

        def deep_freeze(value)
          case value
            when Array
              value.each { |item| deep_freeze(item) }
            when Hash
              value.each do |key, item|
                deep_freeze(key)
                deep_freeze(item)
              end
          end

          value.freeze
        rescue StandardError
          value
        end; module_function :deep_freeze

        def evaluate_default_proc(record, name, default_proc)
          attribute = DefaultAttribute.new(name.to_sym)

          case default_proc.arity
            when 0
              default_proc.call
            when 1
              default_proc.call(record)
            else
              default_proc.call(record, attribute)
          end
        end; module_function :evaluate_default_proc

        # Translate Ruby class to ActiveModel::Attributes type symbol
        #
        def ruby_type_to_am_type(type)
          case
            when type == String   then :string
            when type == Integer  then :integer
            when type == Float    then :float
            when type == Date     then :date
            when type == Time     then :time
            when type == DateTime then :datetime
            when type.respond_to?(:name) && type.name == 'Boolean'  then :boolean
            when type == Elasticsearch::Persistence::Boolean         then :boolean
            when type == Array    then :array
            when type == Hash     then :hash
            else :string
          end
        end; module_function :ruby_type_to_am_type

        # Return Elasticsearch type based on passed Ruby class (used in the `attribute` method)
        #
        def lookup_type(type)
          case
            when type == String
              'text'
            when type == Integer
              'integer'
            when type == Float
              'float'
            when type == Date || type == Time || type == DateTime
              'date'
            when type.respond_to?(:name) && type.name == 'Boolean'
              'boolean'
            when type == Elasticsearch::Persistence::Boolean
              'boolean'
          end
        end; module_function :lookup_type
      end
    end
  end
end

# =============================================================================
# Custom ActiveModel types matching Virtus coercion behavior
# =============================================================================

# Array type — Virtus passed through arrays, returned nil for nil
class VirtusCompatArrayType < ActiveModel::Type::Value
  def cast(value)
    case value
    when Array then value
    when nil then nil
    else Array(value)
    end
  end

  def serialize(value)
    value
  end
end

# Hash type — Virtus passed through hashes, returned nil for nil
class VirtusCompatHashType < ActiveModel::Type::Value
  def cast(value)
    case value
    when Hash then value
    when nil then nil
    else value.to_h rescue nil
    end
  end

  def serialize(value)
    value
  end
end

# Time type — Virtus coerced strings via Time.parse, returned nil on failure
class VirtusCompatTimeType < ActiveModel::Type::Value
  def cast(value)
    case value
    when Time then value
    when DateTime then value.to_time
    when Date then Time.new(value.year, value.month, value.day)
    when String then Time.parse(value) rescue nil
    when nil then nil
    else value
    end
  end
end

# Integer type — Virtus returned nil for non-numeric strings (not 0)
class VirtusCompatIntegerType < ActiveModel::Type::Value
  def cast(value)
    case value
    when Integer then value
    when Float then value.to_i
    when String
      return nil if value.strip.empty?
      # Virtus: "42" -> 42, "abc" -> nil
      Integer(value) rescue nil
    when nil then nil
    else value.to_i rescue nil
    end
  end
end

# Float type — Virtus returned nil for non-numeric strings (not 0.0)
class VirtusCompatFloatType < ActiveModel::Type::Value
  def cast(value)
    case value
    when Float then value
    when Integer then value.to_f
    when String
      return nil if value.strip.empty?
      Float(value) rescue nil
    when nil then nil
    else value.to_f rescue nil
    end
  end
end

# String type — Virtus: true->"true", 123->"123", nil->nil
class VirtusCompatStringType < ActiveModel::Type::Value
  def cast(value)
    case value
    when nil then nil
    else value.to_s
    end
  end
end

# Boolean type — Virtus recognized: false/0/"0"/"false"/"FALSE"/"no"/"NO"/nil as falsy
class VirtusCompatBooleanType < ActiveModel::Type::Value
  FALSY = [false, 0, '0', 'false', 'FALSE', 'no', 'NO', 'off', 'OFF', ''].to_set.freeze

  def cast(value)
    return nil if value.nil?
    !FALSY.include?(value)
  end
end

ActiveModel::Type.register(:array, VirtusCompatArrayType)
ActiveModel::Type.register(:hash, VirtusCompatHashType)
ActiveModel::Type.register(:time, VirtusCompatTimeType)
ActiveModel::Type.register(:integer, VirtusCompatIntegerType)
ActiveModel::Type.register(:float, VirtusCompatFloatType)
ActiveModel::Type.register(:string, VirtusCompatStringType)
ActiveModel::Type.register(:boolean, VirtusCompatBooleanType)
