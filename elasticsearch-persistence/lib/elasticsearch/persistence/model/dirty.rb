require 'ice_nine'
require 'ice_nine/core_ext/object'

module Elasticsearch
  module Persistence
    module Model
      module Dirty
        module ClassMethods #:nodoc:
          # Track each (virtus) attributes
          def attribute(attr_name, *new_properties)
            super
            define_attribute_methods attr_name

            method_str = <<-"EOF_M"
              def #{attr_name}=(new_value)
                #{attr_name}_will_change! unless new_value == attribute_set[:#{attr_name}].get(self)
                super
              end

              def #{attr_name}
                super.deep_freeze
              end
            EOF_M

            class_eval method_str, __FILE__, __LINE__ + 1
          end
        end

        module InstanceMethods #:nodoc:
          def initialize(attributes = {})
            super
            clear_changes_information
          end

          def save(options = {})
            # We introduce an optimisation for all the dirty model
            # By default the save method make a partial update
            if options.delete(:force) == true || !persisted?
              options = { version: _version }.merge(options) if persisted?
              response = super(options)
              changes_applied if response
              response
            else
              run_callbacks :update do
                run_callbacks :save do
                  clear_attribute_changes(changes.select { |k, v| v[0] == v[1] }.keys)
                  response = update(Hash[changes.map { |k, v| [k, v[1]] }], {
                    retry_on_conflict: 3
                  }.merge(options))
                end
              end
              response
            end
          end

          def update(attributes = {}, options = {})
            response = super
            clear_attribute_changes(attributes.keys) if response
            response
          end

          def increment(attribute, value = 1, options = {})
            response = super
            clear_attribute_changes(Array(attribute)) if response
            response
          end

          def decrement(attribute, value = 1, options = {})
            response = super
            clear_attribute_changes(Array(attribute)) if response
            response
          end

          def touch(attribute = :updated_at, options = {})
            response = super
            clear_attribute_changes(Array(attribute)) if response
            response
          end
        end
      end
    end
  end
end
