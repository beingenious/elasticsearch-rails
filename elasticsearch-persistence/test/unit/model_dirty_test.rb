require 'test_helper'

require 'elasticsearch/persistence/model'

class Elasticsearch::Persistence::ModelDirtyTest < Test::Unit::TestCase
  context "The model dirty module" do
    setup do
      class DummyDirtyModel
        include Elasticsearch::Persistence::Model

        attribute :title, String
        attribute :count, Integer, default: 0
        attribute :tags, Array, default: []
        attribute :data, Hash, default: {}
        attribute :nested_data, Hash, default: { nested: [] }
        attribute :enabled, Boolean, default: false
      end

      class DummyDirtyProcModel
        include Elasticsearch::Persistence::Model

        attribute :title, String
        attribute :slug, String,
                  default: lambda { |record, attribute| "#{record.title}-#{attribute.name}" }
      end
    end

    teardown do
      Elasticsearch::Persistence::ModelDirtyTest.__send__ :remove_const, :DummyDirtyModel \
      rescue NameError; nil
      Elasticsearch::Persistence::ModelDirtyTest.__send__ :remove_const, :DummyDirtyProcModel \
      rescue NameError; nil
    end

    # =========================================================================
    # Initialization
    # =========================================================================

    context "on a new record" do
      should "not be changed after initialization with symbol keys" do
        model = DummyDirtyModel.new title: 'Test'
        assert !model.changed?, "Expected model not to be changed after init, but it was: #{model.changes.inspect}"
      end

      should "not be changed after initialization with string keys" do
        model = DummyDirtyModel.new 'title' => 'Test', 'count' => 5
        assert !model.changed?, "Expected model not to be changed after init with string keys"
        assert_equal 'Test', model.title
        assert_equal 5, model.count
      end

      should "have no changes after initialization" do
        model = DummyDirtyModel.new title: 'Test', count: 5
        assert_equal({}, model.changes)
      end

      should "accept mixed symbol and string keys" do
        model = DummyDirtyModel.new title: 'Test', 'count' => 3
        assert_equal 'Test', model.title
        assert_equal 3, model.count
      end

      should "apply default values without marking as changed" do
        model = DummyDirtyModel.new title: 'Test'
        assert_equal 0, model.count
        assert_equal [], model.tags
        assert_equal({}, model.data)
        assert_equal false, model.enabled
        assert !model.changed?
      end

      should "evaluate virtus-style proc defaults with record context" do
        model = DummyDirtyProcModel.new title: 'Test'

        assert_equal 'Test-slug', model.slug
        assert !model.changed?
      end

      should "deep copy nested mutable defaults per instance" do
        first = DummyDirtyModel.new title: 'One'
        second = DummyDirtyModel.new title: 'Two'

        assert_not_equal first.nested_data[:nested].object_id,
                         second.nested_data[:nested].object_id
        assert_equal [], second.nested_data[:nested]
      end
    end

    # =========================================================================
    # Tracking attribute changes
    # =========================================================================

    context "tracking attribute changes" do
      setup do
        @model = DummyDirtyModel.new title: 'Original', count: 0
      end

      should "track string attribute changes" do
        @model.title = 'Updated'
        assert @model.changed?
        assert @model.title_changed?
        assert_equal ['Original', 'Updated'], @model.title_change
      end

      should "track integer attribute changes" do
        @model.count = 5
        assert @model.count_changed?
        assert_equal [0, 5], @model.count_change
      end

      should "track boolean attribute changes" do
        @model.enabled = true
        assert @model.enabled_changed?
        assert_equal [false, true], @model.enabled_change
      end

      should "track array attribute changes" do
        @model.tags = ['ruby', 'rails']
        assert @model.tags_changed?
        assert_equal [[], ['ruby', 'rails']], @model.tags_change
      end

      should "track hash attribute changes" do
        @model.data = { key: 'value' }
        assert @model.data_changed?
        assert_equal [{}, { key: 'value' }], @model.data_change
      end

      should "not mark as changed when same value is assigned" do
        @model.title = 'Original'
        assert !@model.title_changed?, "Expected title not to be changed when same value assigned"
      end

      should "not mark integer as changed when same value is assigned" do
        @model.count = 0
        assert !@model.count_changed?, "Expected count not to be changed when same value assigned"
      end

      should "not mark integer as changed when equivalent string is assigned" do
        @model.count = '0'
        assert !@model.count_changed?, "Expected count not to be changed when equivalent string assigned"
        assert !@model.changed?, "Expected model not to be changed when equivalent integer string assigned"
      end

      should "not mark boolean as changed when equivalent string is assigned" do
        @model.enabled = '0'
        assert !@model.enabled_changed?, "Expected enabled not to be changed when equivalent string assigned"
        assert !@model.changed?, "Expected model not to be changed when equivalent boolean string assigned"
      end

      should "list changed attributes" do
        @model.title = 'New Title'
        @model.count = 10
        assert_equal ['count', 'title'], @model.changed.sort
      end

      should "provide previous values" do
        @model.title = 'New Title'
        assert_equal 'Original', @model.title_was
      end

      should "track multiple sequential changes to same attribute" do
        @model.title = 'First'
        @model.title = 'Second'
        # _was should still be the original value
        assert_equal 'Original', @model.title_was
        assert_equal ['Original', 'Second'], @model.title_change
      end
    end

    # =========================================================================
    # Bulk assignment via attributes= (the real-world pattern)
    # =========================================================================

    context "bulk assignment via attributes=" do
      setup do
        @model = DummyDirtyModel.new title: 'Original', count: 0, enabled: false
      end

      should "track changes from attributes= with symbol keys" do
        @model.attributes = { title: 'Bulk Updated', count: 10 }
        assert @model.changed?
        assert @model.title_changed?
        assert @model.count_changed?
        assert_equal 'Bulk Updated', @model.title
        assert_equal 10, @model.count
      end

      should "track changes from attributes= with string keys" do
        @model.attributes = { 'title' => 'Bulk Updated', 'enabled' => true }
        assert @model.changed?
        assert @model.title_changed?
        assert @model.enabled_changed?
        assert_equal 'Bulk Updated', @model.title
        assert_equal true, @model.enabled
      end

      should "not mark unchanged attributes from partial bulk assignment" do
        @model.attributes = { title: 'New Title' }
        assert @model.title_changed?
        assert !@model.count_changed?, "Expected count not to be changed after partial bulk assign"
        assert !@model.enabled_changed?, "Expected enabled not to be changed after partial bulk assign"
      end

      should "not mark coerced-equivalent attributes as changed in bulk assignment" do
        @model.attributes = { 'count' => '0', 'enabled' => '0' }
        assert !@model.changed?, "Expected model not to be changed when coerced values stay the same"
      end

      should "support the assign-then-save pattern used in the app" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:save).returns({'_id' => 'abc123'})

        # First save to persist
        @model.save
        @model.instance_variable_set(:@persisted, true)

        # Then bulk assign + conditional save (real-world pattern)
        @model.attributes = { title: 'Updated via params' }
        assert @model.changed?

        gateway.expects(:update)
          .with do |id, options|
            assert_equal 'abc123', id
            assert_equal 'Updated via params', options[:doc]['title']
            true
          end
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save
        assert !@model.changed?, "Expected model not to be changed after save"
      end

      should "skip save when nothing changed (conditional save pattern)" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:save).returns({'_id' => 'abc123'})

        @model.save
        @model.instance_variable_set(:@persisted, true)

        # Assign same values — nothing should change
        @model.attributes = { title: 'Original' }
        assert !@model.changed?, "Expected model not to be changed when same values assigned"

        # Gateway should NOT receive any update call
        gateway.expects(:update).never
        gateway.expects(:save).never

        # App pattern: `model.save if model.changed?`
        @model.save if @model.changed?
      end
    end

    # =========================================================================
    # Clearing changes after persistence operations
    # =========================================================================

    context "clearing changes" do
      setup do
        @model = DummyDirtyModel.new title: 'Original'
        @model.title = 'Updated'
      end

      should "clear changes on save" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:save).returns({'_id' => 'abc123'})

        @model.save
        assert !@model.changed?, "Expected model not to be changed after save"
      end

      should "clear changes on update" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:update).returns({'_id' => 'abc123', '_version' => 2})

        @model.instance_variable_set(:@persisted, true)
        @model.instance_variable_set(:@_id, 'abc123')

        @model.update(title: 'Updated')
        assert !@model.title_changed?, "Expected title not to be changed after update"
      end

      should "clear changes on increment" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:update).returns({'_id' => 'abc123', '_version' => 2})

        @model.instance_variable_set(:@persisted, true)
        @model.instance_variable_set(:@_id, 'abc123')

        @model.count = 5
        assert @model.count_changed?

        @model.increment(:count)
        assert !@model.count_changed?, "Expected count not to be changed after increment"
      end

      should "clear changes on decrement" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:update).returns({'_id' => 'abc123', '_version' => 2})

        @model.instance_variable_set(:@persisted, true)
        @model.instance_variable_set(:@_id, 'abc123')

        @model.count = 5
        assert @model.count_changed?

        @model.decrement(:count)
        assert !@model.count_changed?, "Expected count not to be changed after decrement"
      end

      should "clear changes on touch" do
        gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(gateway)
        gateway.expects(:update).returns({'_id' => 'abc123', '_version' => 2})

        @model.instance_variable_set(:@persisted, true)
        @model.instance_variable_set(:@_id, 'abc123')

        @model.touch
        assert !@model.updated_at_changed?, "Expected updated_at not to be changed after touch"
      end
    end

    # =========================================================================
    # Dirty-based partial save optimization
    # =========================================================================

    context "dirty-based partial save optimization" do
      setup do
        @gateway = stub
        DummyDirtyModel.stubs(:gateway).returns(@gateway)

        @model = DummyDirtyModel.new title: 'Original', count: 0
        @gateway.expects(:save).returns({'_id' => 'abc123'})
        @model.save
        @model.instance_variable_set(:@persisted, true)
      end

      should "use partial update when saving a persisted model with changes" do
        @model.title = 'Updated'

        @gateway
          .expects(:update)
          .with do |id, options|
            assert_equal 'abc123', id
            assert_equal 'Updated', options[:doc]['title']
            true
          end
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save
      end

      should "skip unchanged attributes in partial update" do
        @model.title = 'Updated'

        @gateway
          .expects(:update)
          .with do |id, options|
            assert_equal 'abc123', id
            assert options[:doc].key?('title'), "Expected doc to contain 'title'"
            assert !options[:doc].key?('count'), "Expected doc NOT to contain 'count'"
            true
          end
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save
      end

      should "do full save when force option is passed" do
        @model.title = 'Updated'

        @gateway
          .expects(:save)
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save(force: true)
      end

      should "pass extra options through to gateway on partial update" do
        @model.title = 'Updated'

        @gateway
          .expects(:update)
          .with do |id, options|
            assert_equal 3, options[:retry_on_conflict]
            true
          end
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save
      end

      should "pass refresh option through on full save" do
        @gateway
          .expects(:save)
          .with do |object, options|
            assert_equal true, options[:refresh]
            true
          end
          .returns({'_id' => 'abc123', '_version' => 2})

        @model.save(force: true, refresh: true)
      end
    end

    # =========================================================================
    # Serialization (as_json / attributes)
    # =========================================================================

    context "serialization" do
      should "include all attributes in as_json" do
        model = DummyDirtyModel.new title: 'Test', count: 5, enabled: true
        json = model.as_json

        assert_equal 'Test', json['title'] || json[:title]
        assert_equal 5, json['count'] || json[:count]
        assert_equal true, json['enabled'] || json[:enabled]
      end

      should "include id in attributes hash" do
        model = DummyDirtyModel.new id: 'abc123', title: 'Test'
        assert_equal 'abc123', model.attributes[:id]
      end

      should "include default values in attributes" do
        model = DummyDirtyModel.new title: 'Test'
        attrs = model.attributes
        assert_equal 0, attrs[:count]
        assert_equal false, attrs[:enabled]
      end

      should "serialize hash and array attributes correctly" do
        model = DummyDirtyModel.new title: 'Test', tags: ['a', 'b'], data: { key: 'val' }
        json = model.as_json

        tags = json['tags'] || json[:tags]
        data = json['data'] || json[:data]
        assert_equal ['a', 'b'], tags
        assert_equal 'val', (data['key'] || data[:key])
      end
    end

    # =========================================================================
    # Frozen attribute getters (ice_nine deep_freeze)
    # =========================================================================

    context "reading frozen attributes" do
      should "return frozen values for attributes" do
        model = DummyDirtyModel.new title: 'Test', tags: ['a', 'b'], data: { key: 'val' }

        assert model.title.frozen?, "Expected title to be frozen"
        assert model.tags.frozen?, "Expected tags to be frozen"
        assert model.data.frozen?, "Expected data to be frozen"
      end

      should "still allow setting new values via setter" do
        model = DummyDirtyModel.new title: 'Test'
        model.title = 'New Value'
        assert_equal 'New Value', model.title
      end

      should "return frozen default values" do
        model = DummyDirtyModel.new title: 'Test'
        assert model.tags.frozen?, "Expected default tags to be frozen"
        assert model.data.frozen?, "Expected default data to be frozen"
      end

      should "deep freeze nested values for attributes" do
        model = DummyDirtyModel.new title: 'Test', nested_data: { nested: ['value'] }

        assert model.nested_data.frozen?, "Expected nested_data to be frozen"
        assert model.nested_data[:nested].frozen?, "Expected nested array to be frozen"
        assert_raise(FrozenError) { model.nested_data[:nested] << 'another' }
      end
    end
  end
end
