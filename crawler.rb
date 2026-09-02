# frozen_string_literal: true

require "fileutils"

require "relaton/ogc/data_fetcher"
require_relative "index_builder"

FileUtils.rm_rf "data"
# Match only the generated `index-*` outputs (index-v1.yaml, index-v2.yaml and
# their zips) -- NOT the `index_builder.rb` source this crawler requires, which a
# bare `index*` glob would delete out from under the next run.
# spec/crawler_sources_spec.rb guards this.
FileUtils.rm Dir.glob("index-*")

# Writes index-v2.yaml only.
Relaton::Ogc::DataFetcher.fetch

# index-v1 (the legacy string-keyed index): rebuilt here over the data/ tree,
# because released relaton versions still read index-v1.zip from this branch.
# Same arrangement as relaton-data-etsi and relaton-data-3gpp.
#
# Zipping and committing are not done here -- relaton/support's shared
# crawler.yml zips every index*.yaml and commits both the yaml and the zip.
OgcIndexBuilder.build_index_v1
