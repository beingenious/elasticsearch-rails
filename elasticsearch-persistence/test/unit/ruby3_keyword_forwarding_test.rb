require 'test/unit'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
$LOAD_PATH.unshift File.expand_path('../../../elasticsearch-model/lib', __dir__)

gem 'hashie', '~> 3.6.0'

require 'elasticsearch/persistence'

class ElasticsearchPersistenceRuby3KeywordForwardingTest < Test::Unit::TestCase
  def test_repository_forwards_keyword_arguments_to_gateway
    repository = Class.new do
      include Elasticsearch::Persistence::Repository
    end.new

    repository.gateway.define_singleton_method(:with_keywords) do |limit:, **options|
      [limit, options]
    end

    assert_equal [2, { include_scores: true }],
                 repository.with_keywords(limit: 2, include_scores: true)
  end

  def test_results_forwards_keyword_arguments_to_wrapped_results
    wrapped_results = Object.new
    def wrapped_results.with_keywords(limit:, **options)
      [limit, options]
    end

    results = Elasticsearch::Persistence::Repository::Response::Results.allocate
    results.define_singleton_method(:results) { wrapped_results }

    assert_equal [3, { include_scores: true }],
                 results.with_keywords(limit: 3, include_scores: true)
  end
end
