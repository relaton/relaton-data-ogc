# frozen_string_literal: true

require "relaton/ogc/data_fetcher"

FileUtils.rm_rf "data"
FileUtils.rm Dir.glob("index*")

Relaton::Ogc::DataFetcher.fetch
