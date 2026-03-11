require 'test/unit'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

gem 'hashie', '~> 3.6.0'

require 'elasticsearch/model'

class ElasticsearchModelRuby3KeywordForwardingTest < Test::Unit::TestCase
  def test_proxy_method_missing_forwards_keyword_arguments
    target = Object.new
    def target.with_keywords(limit:, **options)
      [limit, options]
    end

    proxy = Elasticsearch::Model::Proxy::InstanceMethodsProxy.new(target)

    assert_equal [2, { include_scores: true }],
                 proxy.with_keywords(limit: 2, include_scores: true)
  end

  def test_instance_proxy_as_indexed_json_forwards_keyword_arguments
    target = Object.new
    def target.as_indexed_json(include_root: false)
      { include_root: include_root }
    end

    proxy = Elasticsearch::Model::Proxy::InstanceMethodsProxy.new(target)

    assert_equal({ include_root: true }, proxy.as_indexed_json(include_root: true))
  end

  def test_response_records_forwards_keyword_arguments
    wrapped_records = Object.new
    def wrapped_records.with_keywords(limit:, **options)
      [limit, options]
    end

    records = Elasticsearch::Model::Response::Records.allocate
    records.define_singleton_method(:records) { wrapped_records }

    assert_equal [3, { include_scores: true }],
                 records.with_keywords(limit: 3, include_scores: true)
  end

  def test_response_result_forwards_keyword_arguments
    source = Object.new
    def source.with_keywords(limit:, **options)
      [limit, options]
    end

    result = Elasticsearch::Model::Response::Result.allocate
    result.instance_variable_set(:@result, source)

    assert_equal [4, { include_scores: true }],
                 result.with_keywords(limit: 4, include_scores: true)
  end
end
