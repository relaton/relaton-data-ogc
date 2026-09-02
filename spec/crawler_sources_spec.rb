# frozen_string_literal: true

# crawler.rb wipes data/ and fetches on load, so it cannot be required. Read it
# as source text instead, the way relaton-data-etsi guards its own.
RSpec.describe "crawler.rb" do
  let(:source) { File.read(File.join(REPO_ROOT, "crawler.rb")) }

  # A bare `index*` glob also matches index_builder.rb and would delete the very
  # file the crawler requires. relaton-data-bipm and relaton-data-iana hit this.
  it "removes only the generated index-* outputs, not index_builder.rb" do
    globs = source.scan(/Dir\.glob\(["']([^"']+)["']\)/).flatten
    expect(globs).not_to be_empty
    globs.each do |glob|
      expect(File.fnmatch(glob, "index_builder.rb")).to be(false),
                                                        "glob #{glob.inspect} matches index_builder.rb"
      expect(File.fnmatch(glob, "index-v1.yaml")).to be(true)
    end
  end

  # Relaton::Ogc::DataFetcher writes index-v2 only. index-v1 is rebuilt from the
  # data/ tree the fetch just produced, so it has to run after it.
  it "builds index-v1 after the fetch" do
    fetch = source.index("Relaton::Ogc::DataFetcher.fetch")
    build = source.index("OgcIndexBuilder.build_index_v1")
    expect(fetch).not_to be_nil
    expect(build).not_to be_nil
    expect(build).to be > fetch
  end
end
