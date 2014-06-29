module Elasticsearch
  module Persistence
    module Model
      # This module contains the Dirty interface for models
      #
      module Dirty

        module ClassMethods #:nodoc:

          # Track each attributes
          def attribute(attr_name, *new_properties)
            super
            define_attribute_methods attr_name

            method_str = <<-"EOF_M"
              def #{attr_name}=(new_value)
                #{attr_name}_will_change! unless new_value == attribute_set[:#{attr_name}].get(self)
                super
              end
            EOF_M

            class_eval method_str, __FILE__, __LINE__ + 1
          end
        end

        module InstanceMethods

          # Model initializer reset the changes information
          def initialize(attributes={})
            super
            reset_changes
          end

          # Removes current changes and makes them accessible through +previous_changes+.
          def save(options={})
            changes_applied if response = super
            response
          end

          def update(attributes={}, options={})
            attributes_changes_applied!(attributes.keys) if response = super
            response
          end

          def increment(attribute, value=1, options={})
            attributes_changes_applied!(Array(attribute)) if response = super
            response
          end

          def decrement(attribute, value=1, options={})
            attributes_changes_applied!(Array(attribute)) if response = super
            response
          end

          def touch(attribute=:updated_at, options={})
            attributes_changes_applied!(Array(attribute)) if response = super
            response
          end

          # Removes specific attributes changes and makes it accessible through +previous_changes+.
          def attributes_changes_applied!(attributes)
            @previously_changed = ActiveSupport::HashWithIndifferentAccess[attributes.map { |attr| [attr, attribute_change(attr)] }]
            attributes.each { |attr| @changed_attributes.delete(attr) }
          end

        end
      end
    end
  end
end
