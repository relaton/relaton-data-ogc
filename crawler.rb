# frozen_string_literal: true

require "relaton_ogc"

FileUtils.rm_rf "data"
FileUtils.rm Dir.glob("index*")

RelatonOgc::DataFetcher.fetch
