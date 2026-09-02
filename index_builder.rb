# frozen_string_literal: true

require "date"
require "yaml"

# Builds the legacy `index-v1.yaml` this repository publishes.
#
# `Relaton::Ogc::DataFetcher` writes only the pubid-structured `index-v2.yaml`
# (`relaton/lib/relaton/ogc.rb`, `INDEXFILE = "index-v2"`, and
# `pubid_class: ::Pubid::Ogc::Identifier` on the producer). Released `relaton`
# versions still download `index-v1.zip` from this branch, so the crawler keeps
# producing it here. relaton-data-etsi, relaton-data-3gpp, relaton-data-iana,
# relaton-data-ccsds and relaton-data-bipm carry the same arrangement.
#
# Without this, `index-v1.yaml` is simply never rewritten: crawler.rb deletes it
# on disk, but relaton/support's shared crawler.yml stages the indexes with the
# shell glob `git add index*.yaml`, which matches only files that still exist,
# so the deletion is never committed and the old blob stays frozen at HEAD. That
# is what metanorma/metanorma-pdfa#95 reports -- a row naming a data file the
# crawl had since deleted, which the client resolves to a 404 and reports as
# "Not found".
#
# The rows come from the `data/` tree and from nothing else. Each row's id is
# the document's primary docidentifier, which is the string
# `Relaton::Ogc::DataFetcher#write_document` indexed on before the v2 change and
# therefore the string the released client searches for. Only that one field is
# read -- no bibitem deserialization -- so data-model drift in the relaton gem
# cannot break the rebuild.
#
# No pubid is needed at all: an OGC v1 id is the docidentifier verbatim, so this
# runs in the crawler's own process instead of a child with a legacy bundle.
#
# Verbatim means verbatim. The corpus holds `11-038R2` (uppercase revision) and
# `20-001r2 ` (trailing space); the old fetcher indexed both as they stand, so
# the released client searches for them as they stand. `index-v2` canonicalizes
# them through pubid -- that is a v2 concern and must not leak back into v1.
#
# It does not read `index-v2.yaml`, and cannot usefully cross-check against it:
# `Relaton::Ogc::DataFetcher#write_document` writes the data file and adds the
# v2 index row in one method, returning before either when the id is a
# duplicate, so the two always agree by construction. A truncated crawl leaves
# them short together, which no comparison between them can see.
module OgcIndexBuilder
  Error = Class.new(StandardError)

  DATA_GLOB = "data/*.yaml"
  INDEX_V1 = "index-v1.yaml"

  module_function

  # The index-v1 rows: `{ id: <primary docidentifier>, file: <path> }` in sorted
  # glob order.
  #
  # Raises when any data file yields no id. Every document in `data/` must reach
  # the index: dropping one silently is the divergence that produced
  # metanorma/metanorma-pdfa#95, and a red crawl is cheaper to notice than an
  # index that is quietly one record short.
  def rows(glob: DATA_GLOB)
    found = primary_docids(glob: glob)
    check_complete! found
    check_unique! found
    found.map { |file, id| { id: id, file: file } }
  end

  # Rebuild INDEX_V1 from the data/ tree. Writes nothing if a document cannot be
  # indexed, so a short walk cannot publish a truncated index.
  def build_index_v1(file: INDEX_V1, glob: DATA_GLOB)
    data_rows = rows(glob: glob)

    File.write file, data_rows.to_yaml
    puts "index-v1: wrote #{data_rows.size} entries to #{file}"
    data_rows
  end

  # -- internals ------------------------------------------------------------

  # `{ file => id }` for every data file, in sorted glob order, with the id left
  # nil where it could not be read. One unreadable document must not abort the
  # walk before the others are reported, so the failure is collected here and
  # raised once in .check_complete!.
  def primary_docids(glob: DATA_GLOB)
    Dir[glob].sort.to_h do |file|
      [file, begin
        primary_docid(file)
      rescue StandardError => e
        warn "index-v1: cannot read the docidentifier of #{file}: #{e.class}: #{e.message}"
        nil
      end]
    end
  end

  # The content of the document's primary docidentifier.
  #
  # `Relaton::Ogc::DataFetcher#write_document` indexes
  # `bib.docidentifier[0].content`, and every record in the corpus carries
  # exactly one docidentifier, marked primary. Keying on `primary` rather than
  # on position means a record that ever carries a second identifier -- an ISO
  # number on a co-published document, say -- still indexes under the one the
  # client searches for.
  #
  # Date and Time are permitted because Psych instantiates them: OGC writes
  # `at: '2024-02-06'` quoted, which stays a String, but one record with an
  # unquoted date would otherwise raise Psych::DisallowedClass and fail the
  # whole rebuild.
  def primary_docid(file)
    doc = YAML.safe_load_file(file, permitted_classes: [Date, Time])
    return nil unless doc.is_a? Hash

    primary = Array(doc["docidentifier"]).find { |d| d.is_a?(Hash) && d["primary"] }
    primary && primary["content"]
  end

  def check_complete!(found)
    lost = found.select { |_file, id| id.to_s.empty? }.keys
    return if lost.empty?

    raise Error, "index-v1: #{lost.size} document(s) in #{DATA_GLOB} yielded no " \
                 "primary docidentifier, so the index would publish short of " \
                 "the corpus:\n#{lost.first(20).map { |f| "  #{f}" }.join("\n")}"
  end

  # A v1 index cannot hold two rows with the same id: the fetcher indexed
  # through `Relaton::Index::Type#add_or_update`, which is keyed on `id.to_s`
  # and overwrites. A plain walk of `data/` can, and would publish an index
  # whose duplicate rows resolve to whichever file the client's scan reaches
  # first. Fail the crawl instead.
  def check_unique!(found)
    dups = found.group_by { |_file, id| id }.select { |_id, pairs| pairs.size > 1 }
    return if dups.empty?

    detail = dups.first(20).map { |id, pairs| "  #{id}: #{pairs.map(&:first).join(', ')}" }
    raise Error, "index-v1: #{dups.size} duplicated id(s) in #{DATA_GLOB}:\n#{detail.join("\n")}"
  end
end
