# frozen_string_literal: true

RSpec.describe OgcIndexBuilder do
  # A document with many revisions, and a recent one. `let`, not constants: a
  # constant assigned inside a `describe` block lands on Object, not on the
  # example group, and leaks into every other spec file.
  let(:id128) { "12-128r19" }
  let(:id015) { "26-015r1" }

  describe ".rows" do
    it "reads the primary docidentifier of every data file, in sorted glob order" do
      in_workdir("data/b.yaml" => doc(id015), "data/a.yaml" => doc(id128)) do
        expect(described_class.rows).to eq(
          [{ id: id128, file: "data/a.yaml" },
           { id: id015, file: "data/b.yaml" }],
        )
      end
    end

    # `docidentifier[0]` is what Relaton::Ogc::DataFetcher#write_document
    # happens to index on, and every record in the corpus carries exactly one.
    # Keying on `primary` instead means a record that ever carries two still
    # indexes under the identifier the client searches for.
    it "picks the primary docidentifier, not the first one" do
      in_workdir("data/a.yaml" => doc(id015, [{ "content" => "ISO 19115-1", "type" => "ISO" }])) do
        expect(described_class.rows.first[:id]).to eq(id015)
      end
    end

    it "ignores id, which is not what the fetcher indexes on" do
      in_workdir("data/a.yaml" => { "id" => "26015r1",
                                    "docidentifier" => [{ "content" => id015, "primary" => true }] }) do
        expect(described_class.rows.first[:id]).to eq(id015)
      end
    end

    # The old fetcher indexed the docidentifier verbatim, so the released client
    # searches for it verbatim. index-v2 canonicalizes these two through pubid;
    # that must not leak back into v1.
    it "passes an uppercase revision and a trailing space through unchanged" do
      in_workdir("data/a.yaml" => doc("11-038R2"), "data/b.yaml" => doc("20-001r2 ")) do
        expect(described_class.rows.map { |r| r[:id] }).to eq(["11-038R2", "20-001r2 "])
      end
    end

    # Every data file must reach the index. Skipping one silently is the failure
    # that produced metanorma/metanorma-pdfa#95, so it is fatal, not a warning.
    it "raises, naming the file, when a document has no primary docidentifier" do
      in_workdir("data/a.yaml" => { "docidentifier" => [{ "content" => id015 }] },
                 "data/b.yaml" => doc(id128)) do
        expect { described_class.rows }
          .to raise_error(OgcIndexBuilder::Error, %r{data/a\.yaml})
      end
    end

    it "raises, after reporting why, when a document is unparseable" do
      in_workdir("data/a.yaml" => doc(id015),
                 "data/bad.yaml" => "docidentifier: [unterminated\n") do
        expect { expect { described_class.rows }.to raise_error(OgcIndexBuilder::Error, %r{data/bad\.yaml}) }
          .to output(%r{data/bad\.yaml: Psych::SyntaxError}).to_stderr
      end
    end

    # Relaton::Index::Type#add_or_update is keyed on `id.to_s` and overwrites, so
    # a v1 index could never hold two rows with the same id. A plain walk of
    # data/ can.
    it "raises, naming both files, on a duplicated id" do
      in_workdir("data/a.yaml" => doc(id015), "data/b.yaml" => doc(id015)) do
        expect { described_class.rows }
          .to raise_error(OgcIndexBuilder::Error, %r{data/a\.yaml, data/b\.yaml})
      end
    end

    # OGC quotes its dates, so they stay strings, but one unquoted `at:` would
    # raise Psych::DisallowedClass under a bare safe_load and take the whole
    # rebuild with it.
    it "reads a document carrying an unquoted date" do
      in_workdir("data/a.yaml" => "docidentifier:\n- content: #{id015}\n  primary: true\n" \
                                  "date:\n- type: published\n  at: 2026-08-31\n") do
        expect(described_class.rows.first[:id]).to eq(id015)
      end
    end
  end

  describe ".build_index_v1" do
    it "writes the rows as YAML and reports the count" do
      in_workdir("data/a.yaml" => doc(id128), "data/b.yaml" => doc(id015)) do
        expect { described_class.build_index_v1 }
          .to output(/index-v1: wrote 2 entries to index-v1\.yaml/).to_stdout
        expect(YAML.safe_load_file("index-v1.yaml", permitted_classes: [Symbol]))
          .to eq([{ id: id128, file: "data/a.yaml" },
                  { id: id015, file: "data/b.yaml" }])
      end
    end

    it "writes nothing when a document cannot be indexed" do
      in_workdir("data/a.yaml" => { "docidentifier" => [] }) do
        expect { described_class.build_index_v1 }.to raise_error(OgcIndexBuilder::Error)
        expect(File.exist?("index-v1.yaml")).to be(false)
      end
    end
  end

  # The check the plan ran by hand: the rebuild must reproduce the committed
  # index exactly, as a set. Order differs -- the old file is in crawl order.
  describe "against the committed corpus" do
    it "reproduces every row of index-v1.yaml" do
      Dir.chdir(REPO_ROOT) do
        committed = YAML.safe_load_file("index-v1.yaml", permitted_classes: [Symbol, Date, Time])
        rebuilt = described_class.rows
        expect(rebuilt.map { |r| [r[:id], r[:file]] }.sort)
          .to eq(committed.map { |r| [r[:id], r[:file]] }.sort)
      end
    end
  end
end
